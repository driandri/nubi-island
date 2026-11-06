import AppKit
import Foundation

enum YouTubeBrowserError: LocalizedError {
    case unavailable
    case automation(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "No playing YouTube tab in Chrome"
        case .automation(let detail): "Chrome YouTube detection needs Automation access and Chrome → View → Developer → Allow JavaScript from Apple Events. \(detail)"
        }
    }
}

private struct YouTubePayload: Decodable {
    let url: String
    let title: String
    let artist: String
    let duration: Double
    let position: Double
    let playing: Bool
    let artwork: String?
}

struct YouTubeTabCandidate {
    let url: String
    let snapshot: PlaybackSnapshot
}

enum YouTubeTabSelection {
    static func choose(_ candidates: [YouTubeTabCandidate], preferredURL: String?) -> YouTubeTabCandidate? {
        candidates.first(where: { $0.snapshot.playing })
            ?? candidates.first(where: { $0.url == preferredURL })
            ?? candidates.first
    }
}

/// Chrome's public AppleScript dictionary exposes tabs and JavaScript execution.
/// Only youtube.com watch tabs are inspected; no page content is retained.
actor YouTubeBridge {
    private var cached: (date: Date, snapshot: PlaybackSnapshot)?
    private var preferredTabURL: String?

    func playing() throws -> Bool { try snapshot().playing }

    func snapshot() throws -> PlaybackSnapshot {
        if let cached, Date().timeIntervalSince(cached.date) < 0.8 { return cached.snapshot }
        let script = """
        tell application id "com.google.Chrome"
            set matches to {}
            set sawYouTube to false
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if (tabURL starts with "https://www.youtube.com/" or tabURL starts with "https://youtube.com/" or tabURL starts with "https://music.youtube.com/" or tabURL starts with "https://m.youtube.com/") and (tabURL contains "/watch?" or tabURL contains "/live/" or tabURL contains "/shorts/" or tabURL contains "/embed/") then
                        set sawYouTube to true
                        try
                            set payload to execute browserTab javascript \(Self.appleScriptString(Self.probeJavaScript))
                            if payload is not missing value and payload is not "" then set end of matches to payload
                        end try
                    end if
                end repeat
            end repeat
            if sawYouTube and (count of matches) is 0 then set end of matches to "notch:javascript-unavailable"
            return matches
        end tell
        """
        let result = try execute(script)
        var candidates: [YouTubeTabCandidate] = []
        for index in 0..<result.numberOfItems {
            guard let raw = result.atIndex(index + 1)?.stringValue else { continue }
            if raw == "notch:javascript-unavailable" {
                throw YouTubeBrowserError.automation("Enable the Chrome setting, then retry detection in Nubi Settings.")
            }
            guard
                  let data = raw.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(YouTubePayload.self, from: data),
                  !payload.title.isEmpty else { continue }
            let artworkURL = payload.artwork.flatMap(URL.init(string:)).flatMap { url -> URL? in
                guard url.scheme == "https", let host = url.host,
                      host == "i.ytimg.com" || host == "img.youtube.com" else { return nil }
                return url
            }
            let snapshot = PlaybackSnapshot(title: payload.title, artist: payload.artist,
                                            duration: payload.duration, position: payload.position,
                                            playing: payload.playing, artwork: nil, artworkURL: artworkURL)
            candidates.append(YouTubeTabCandidate(url: payload.url, snapshot: snapshot))
        }
        guard let selected = YouTubeTabSelection.choose(candidates, preferredURL: preferredTabURL) else {
            throw YouTubeBrowserError.unavailable
        }
        preferredTabURL = selected.url
        cached = (Date(), selected.snapshot)
        return selected.snapshot
    }

    func command(_ command: String) throws {
        let action: String
        switch command {
        case "PlPs": action = "v.paused ? v.play() : v.pause()"
        case "Next": action = "document.querySelector('.ytp-next-button')?.click()"
        case "Prev": action = "v.currentTime = 0"
        default: return
        }
        let javaScript = "(function(){var v=document.querySelector('video');if(v){\(action);return 'ok'}return ''})()"
        let script = """
        tell application id "com.google.Chrome"
            set fallbackTab to missing value
            set preferredTab to missing value
            set preferredURL to \(Self.appleScriptString(preferredTabURL ?? ""))
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if (tabURL starts with "https://www.youtube.com/" or tabURL starts with "https://youtube.com/" or tabURL starts with "https://music.youtube.com/" or tabURL starts with "https://m.youtube.com/") and (tabURL contains "/watch?" or tabURL contains "/live/" or tabURL contains "/shorts/" or tabURL contains "/embed/") then
                        if fallbackTab is missing value then set fallbackTab to browserTab
                        if tabURL is preferredURL then set preferredTab to browserTab
                        set payload to execute browserTab javascript \(Self.appleScriptString(Self.probeJavaScript))
                        if payload contains "\\\"playing\\\":true" then
                            execute browserTab javascript \(Self.appleScriptString(javaScript))
                            return
                        end if
                    end if
                end repeat
            end repeat
            if preferredTab is not missing value then
                execute preferredTab javascript \(Self.appleScriptString(javaScript))
            else if fallbackTab is not missing value then
                execute fallbackTab javascript \(Self.appleScriptString(javaScript))
            end if
        end tell
        """
        _ = try execute(script)
        cached = nil
    }

    private func execute(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let result { return result }
        let detail = (error?[NSAppleScript.errorMessage] as? String) ?? "Chrome did not return media data."
        throw YouTubeBrowserError.automation(detail)
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static let probeJavaScript = """
    (function(){var v=document.querySelector('video');if(!v)return 'notch:no-video';
    var t=document.querySelector("meta[property='og:title']");
    var a=document.querySelector('link[itemprop=name]')||document.querySelector('meta[name=author]');
    var i=document.querySelector("meta[property='og:image']");
    return JSON.stringify({url:location.href,title:(t&&t.content)||document.title.replace(/ - YouTube$/,''),
    artist:(a&&(a.content||a.getAttribute('content')))||'YouTube',
    duration:Number.isFinite(v.duration)?v.duration:0,position:v.currentTime||0,
    playing:!v.paused&&!v.ended,artwork:i&&i.content});})()
    """.replacingOccurrences(of: "\n", with: "")
}

struct LyricLine: Equatable, Sendable {
    let time: TimeInterval?
    let text: String
}

struct LyricsResult: Sendable {
    let lines: [LyricLine]
    let credit: String
}

protocol LyricsService: Sendable {
    func lookup(title: String, artist: String, duration: TimeInterval) async throws -> LyricsResult?
}

private final class LyricsHTTPSRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}

actor LRCLIBLyricsService: LyricsService {
    private struct Response: Decodable { let plainLyrics: String?; let syncedLyrics: String?; let instrumental: Bool }
    private let session: URLSession
    private let redirectGuard = LyricsHTTPSRedirectGuard()
    init(session: URLSession = .shared) { self.session = session }

    func lookup(title: String, artist: String, duration: TimeInterval) async throws -> LyricsResult? {
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if duration >= 1 && duration <= 3600 { components.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        request.setValue("Notch/1.0 (macOS; lyrics lookup)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request, delegate: redirectGuard)
        guard let response = response as? HTTPURLResponse else { return nil }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200, data.count <= 512_000 else { return nil }
        let item = try JSONDecoder().decode(Response.self, from: data)
        if item.instrumental { return nil }
        if let synced = item.syncedLyrics {
            let lines = Self.parseSynced(synced)
            if !lines.isEmpty { return LyricsResult(lines: lines, credit: "Lyrics: LRCLIB") }
        }
        guard let plain = item.plainLyrics else { return nil }
        let lines = plain.split(separator: "\n", omittingEmptySubsequences: false)
            .map { LyricLine(time: nil, text: String($0)) }
        return lines.isEmpty ? nil : LyricsResult(lines: lines, credit: "Lyrics: LRCLIB")
    }

    static func parseSynced(_ value: String) -> [LyricLine] {
        value.split(separator: "\n").compactMap { raw in
            let row = String(raw)
            guard row.first == "[", let closing = row.firstIndex(of: "]") else { return nil }
            let stamp = row[row.index(after: row.startIndex)..<closing].split(separator: ":")
            guard stamp.count == 2, let minute = Double(stamp[0]), let second = Double(stamp[1]),
                  minute.isFinite, second.isFinite else { return nil }
            let text = row[row.index(after: closing)...].trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : LyricLine(time: minute * 60 + second, text: text)
        }.sorted { ($0.time ?? 0) < ($1.time ?? 0) }
    }
}
