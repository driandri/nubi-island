import Combine
import Foundation

struct DownloadItem: Identifiable {
    enum State: Equatable { case running, completed, failed(String), cancelled }
    let id: UUID
    let url: URL
    let destination: URL
    var progress: Double = 0
    var state: State = .running
    var name: String { destination.lastPathComponent }
}

struct DownloadFailure: Error, Sendable { let message: String }

final class DownloadCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = Set<UUID>()
    private var committed = Set<UUID>()
    @discardableResult func cancel(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !committed.contains(id) else { return false }
        cancelled.insert(id)
        return true
    }
    func performIfActive(_ id: UUID, _ operation: () throws -> Void) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled.contains(id) else { return false }
        try operation()
        committed.insert(id)
        return true
    }
    func clear(_ id: UUID) { lock.lock(); cancelled.remove(id); committed.remove(id); lock.unlock() }
}

final class HTTPSRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { completionHandler(nil); return }
        completionHandler(request)
    }
}

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    private let redirectGuard = HTTPSRedirectGuard()
    private let gate = DownloadCancellationGate()
    private let sessionConfiguration: URLSessionConfiguration
    private lazy var session = URLSession(configuration: sessionConfiguration, delegate: redirectGuard, delegateQueue: nil)
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var progressTimer: Timer?

    init(configuration: URLSessionConfiguration = .default) { sessionConfiguration = configuration }

    static func validatedURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    func start(url: URL, destination: URL) {
        guard url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil,
              destination.isFileURL else { return }
        let id = UUID()
        let gate = self.gate
        let task = session.downloadTask(with: url) { [weak self] temporary, response, error in
            let result: Result<Void, DownloadFailure>
            if let error { result = .failure(DownloadFailure(message: error.localizedDescription)) }
            else if let code = (response as? HTTPURLResponse)?.statusCode, !(200...299).contains(code) {
                result = .failure(DownloadFailure(message: "HTTP \(code)"))
            } else if let temporary {
                do {
                    let saved = try gate.performIfActive(id) {
                        if FileManager.default.fileExists(atPath: destination.path) {
                            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
                        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
                    }
                    result = saved ? .success(()) : .failure(DownloadFailure(message: "Cancelled"))
                } catch { result = .failure(DownloadFailure(message: error.localizedDescription)) }
            } else { result = .failure(DownloadFailure(message: "No file was downloaded")) }
            Task { @MainActor [weak self] in self?.finish(id: id, result: result) }
        }
        items.insert(DownloadItem(id: id, url: url, destination: destination), at: 0)
        var finishedSeen = 0
        items = items.filter { item in
            if item.state == .running { return true }
            finishedSeen += 1
            return finishedSeen <= 20
        }
        tasks[id] = task
        startProgressTimer()
        task.resume()
    }

    private func startProgressTimer() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshProgress() }
        }
    }
    private func refreshProgress() {
        for (id, task) in tasks {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            let value = task.progress.fractionCompleted
            if value.isFinite, value >= 0 { items[index].progress = min(1, value) }
        }
        if tasks.isEmpty { progressTimer?.invalidate(); progressTimer = nil }
    }
    private func finish(id: UUID, result: Result<Void, DownloadFailure>) {
        tasks.removeValue(forKey: id)
        gate.clear(id)
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].state == .running else { return }
        switch result {
        case .success: items[index].progress = 1; items[index].state = .completed
        case .failure(let failure): items[index].state = .failed(failure.message)
        }
        refreshProgress()
    }
    func cancel(_ id: UUID) {
        guard gate.cancel(id) else { return }
        tasks.removeValue(forKey: id)?.cancel()
        if let index = items.firstIndex(where: { $0.id == id }) { items[index].state = .cancelled }
        refreshProgress()
    }
    func stop() {
        for (id, task) in tasks { gate.cancel(id); task.cancel() }
        tasks.removeAll()
        progressTimer?.invalidate(); progressTimer = nil
        session.invalidateAndCancel()
    }
}
