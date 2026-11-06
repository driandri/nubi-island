import AppKit
import XCTest
@testable import NotchShelf

final class FileShelfTests: XCTestCase {
    func testArchiveContainsSelectedFileContents() throws {
        let working = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: working) }
        let source = working.appendingPathComponent("notes.txt")
        try "shelf archive fixture".write(to: source, atomically: true, encoding: .utf8)
        let archive = working.appendingPathComponent("shelf.zip")
        try ShelfArchive.createZIP(files: [source], destination: archive)
        let extracted = working.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, extracted.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: extracted.appendingPathComponent("Nōtch Shelf/notes.txt"), encoding: .utf8), "shelf archive fixture")
    }
    @MainActor
    func testImageOCRBecomesSearchableWithoutNetwork() async throws {
        let working = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: working) }
        let image = NSImage(size: NSSize(width: 800, height: 200))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 800, height: 200).fill()
        ("HELLO NOTE" as NSString).draw(at: NSPoint(x: 35, y: 50), withAttributes: [
            .font: NSFont.systemFont(ofSize: 90, weight: .bold), .foregroundColor: NSColor.black
        ])
        image.unlockFocus()
        let data = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:]))
        let file = working.appendingPathComponent("image.png")
        try data.write(to: file)
        let shelf = FileShelf()
        XCTAssertTrue(shelf.add([file]))
        for _ in 0..<400 where shelf.processingOCR.contains(file) { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(shelf.recognizedText[file]?.localizedStandardContains("HELLO") == true, "OCR text: \(shelf.recognizedText[file] ?? "nil")")
        shelf.searchQuery = "hello"
        XCTAssertEqual(shelf.searchResults, [file])
    }
    @MainActor
    func testInvalidDropDoesNotReportSuccess() {
        let shelf = FileShelf(exists: { _ in false })
        XCTAssertFalse(shelf.add([URL(string: "https://example.com/file")!, URL(fileURLWithPath: "/missing.txt")]))
        XCTAssertTrue(shelf.files.isEmpty)
        XCTAssertNotNil(shelf.error)
    }
    @MainActor
    func testEquivalentPathsDoNotConsumeExtraSlots() {
        let shelf = FileShelf(exists: { _ in true })
        XCTAssertTrue(shelf.add([URL(fileURLWithPath: "/tmp/folder/../file.txt"), URL(fileURLWithPath: "/tmp/file.txt")]))
        XCTAssertEqual(shelf.files, [URL(fileURLWithPath: "/tmp/file.txt")])
    }
    @MainActor
    func testFullShelfRejectsNewFilesButAcceptsExistingReferences() {
        let shelf = FileShelf(exists: { _ in true })
        let urls = (0..<10).map { URL(fileURLWithPath: "/tmp/item-\($0)") }
        XCTAssertTrue(shelf.add(urls))
        XCTAssertEqual(shelf.files.count, 8)
        XCTAssertTrue(shelf.error?.contains("2 item(s) skipped") == true)
        XCTAssertFalse(shelf.add([urls[9]]))
        XCTAssertTrue(shelf.add([urls[0]]))
        XCTAssertEqual(shelf.files.count, 8)
        XCTAssertNil(shelf.error)
    }
    @MainActor
    func testMixedDropKeepsValidFilesAndReportsRejectedItems() {
        let shelf = FileShelf(exists: { $0.lastPathComponent != "missing" })
        let good = URL(fileURLWithPath: "/tmp/good")
        XCTAssertTrue(shelf.add([URL(fileURLWithPath: "/tmp/missing"), good]))
        XCTAssertEqual(shelf.files, [good])
        XCTAssertNotNil(shelf.error)
        shelf.remove(good)
        XCTAssertTrue(shelf.files.isEmpty)
        XCTAssertNil(shelf.error)
    }
    @MainActor
    func testRevealChecksExistenceAgainAndDoesNotOpenMissingFile() {
        var exists = true
        var revealed: [URL] = []
        let shelf = FileShelf(exists: { _ in exists }, revealInFinder: { revealed.append($0) })
        let file = URL(fileURLWithPath: "/tmp/item")
        shelf.add([file])
        shelf.reveal(file)
        XCTAssertEqual(revealed, [file])
        exists = false
        shelf.reveal(file)
        XCTAssertEqual(revealed.count, 1)
        XCTAssertNotNil(shelf.error)
    }
    @MainActor
    func testClearAndRemoveNeverDeleteFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notch-shelf-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("test.txt")
        try Data("Shelf test".utf8).write(to: file)
        let shelf = FileShelf()
        XCTAssertTrue(shelf.add([file]))
        shelf.remove(file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        shelf.add([file])
        shelf.clear()
        XCTAssertTrue(shelf.files.isEmpty)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "Shelf test")
    }
}
