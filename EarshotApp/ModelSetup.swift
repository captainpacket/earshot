// First-run model download (ADR-2611141630): the app fetches the speech and speaker models itself,
// so installing Earshot no longer means pasting curl commands into Terminal.
//
// Each file downloads to a staging folder inside ~/Models, is checked against its pinned SHA-256,
// and only then moves into place (an archive unpacks into staging first). A cancelled, failed or
// tampered download never leaves a file where the scripts would read it.
import AppKit
import Foundation
import SwiftUI

@MainActor
final class ModelDownloader: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var missingRequired: [ModelFile] = []
    @Published private(set) var missingTranslate: [ModelFile] = []
    /// Bytes done across the whole batch, and the batch size.
    @Published private(set) var received: Int64 = 0
    @Published private(set) var total: Int64 = 0
    @Published private(set) var current = ""
    /// Bumped each time a batch finishes, so views can react (for example, transcribe what waited).
    @Published private(set) var finishedCount = 0

    let root: URL
    /// Writes to the app's activity log; Library sets it (file names and results, never what was said).
    var log: (String) -> Void = { _ in }
    /// What the last download asked for, so Try Again retries the same thing.
    private(set) var lastGroups: Set<ModelGroup> = ModelCatalog.required
    private var job: Task<Void, Never>?

    init(root: URL = ModelCatalog.defaultRoot) {
        self.root = root
        refresh()
    }

    /// A downloader frozen in one state, for Tests/RenderUI.swift. It never touches the disk.
    init(previewState: State, missing: [ModelFile], received: Int64 = 0, total: Int64 = 0, current: String = "") {
        root = URL(fileURLWithPath: "/nonexistent")
        state = previewState
        missingRequired = missing
        self.received = received
        self.total = total
        self.current = current
    }

    var needsRequired: Bool { !missingRequired.isEmpty }
    var needsTranslate: Bool { !missingTranslate.isEmpty }
    var isDownloading: Bool { state == .downloading }

    func refresh() {
        missingRequired = ModelCatalog.missing(ModelCatalog.required, root: root)
        missingTranslate = ModelCatalog.missing([.translate], root: root)
    }

    func download(_ groups: Set<ModelGroup>) {
        guard !isDownloading else { return }
        lastGroups = groups
        let files = ModelCatalog.missing(groups, root: root)
        guard !files.isEmpty else { refresh(); return }

        let need = ModelCatalog.totalBytes(files)
        // The staged download and the installed file briefly coexist only for archives (a few MB), so
        // the batch size plus a margin is enough.
        if let free = try? root.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage,
           free < need + 500_000_000 {
            state = .failed("Not enough free disk space. The models need \(ModelCatalog.size(need)) "
                            + "and this Mac has \(ModelCatalog.size(free)) free.")
            return
        }

        state = .downloading
        received = 0
        total = need
        log("models: downloading \(files.map(\.installedPath).joined(separator: ", ")) (\(ModelCatalog.size(need)))")
        let root = self.root
        job = Task {
            var done: Int64 = 0
            do {
                for f in files {
                    current = f.name
                    let base = done
                    try await ModelInstaller.install(f, root: root) { bytes in
                        Task { @MainActor in self.received = base + bytes }
                    }
                    done += f.bytes
                    received = done
                }
                log("models: download finished")
                state = .idle
            } catch is CancellationError {
                log("models: download cancelled")
                state = .idle
            } catch {
                log("models: download failed: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
            current = ""
            job = nil
            // The staging folder only holds files mid-download; do not leave an empty one behind.
            try? FileManager.default.removeItem(at: root.appendingPathComponent(".earshot-download"))
            refresh()
            finishedCount += 1
        }
    }

    func cancel() { job?.cancel() }

}

enum ModelInstallError: LocalizedError {
    case http(Int, String)
    case checksum(String)
    case unpack(String)

    var errorDescription: String? {
        switch self {
        case let .http(code, name): return "\(name): the server answered \(code). Check your internet connection and try again."
        case let .checksum(name): return "\(name): the download did not match the expected file, so it was not installed. Try again."
        case let .unpack(name): return "\(name): the archive could not be unpacked."
        }
    }
}

enum ModelInstaller {
    /// Downloads, verifies and installs one file. `progress` gets bytes received so far for this file.
    static func install(_ f: ModelFile, root: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let fm = FileManager.default
        let staging = root.appendingPathComponent(".earshot-download", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent(f.url.lastPathComponent)
        try? fm.removeItem(at: staged)
        defer { try? fm.removeItem(at: staged) }

        try await FileFetcher(progress: progress).fetch(f.url, to: staged, name: f.name)
        try Task.checkCancellation()

        let hash = try await Task.detached(priority: .utility) { try ModelCatalog.sha256(of: staged) }.value
        guard hash == f.sha256 else { throw ModelInstallError.checksum(f.name) }
        try Task.checkCancellation()

        if f.archive {
            let unpack = staging.appendingPathComponent("unpack-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: unpack, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: unpack) }
            let tar = Process()
            tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tar.arguments = ["-xjf", staged.path, "-C", unpack.path]
            try tar.run()
            tar.waitUntilExit()
            guard tar.terminationStatus == 0 else { throw ModelInstallError.unpack(f.name) }
            let target = ModelCatalog.extractDirectory(for: f, root: root)
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for item in try fm.contentsOfDirectory(atPath: unpack.path) {
                let dest = target.appendingPathComponent(item)
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: unpack.appendingPathComponent(item), to: dest)
            }
            guard (ModelCatalog.fileSize(root.appendingPathComponent(f.installedPath).path) ?? 0) > 0 else {
                throw ModelInstallError.unpack(f.name)
            }
        } else {
            let dest = ModelCatalog.destination(for: f, root: root)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            // URLSession's temporary file is owner-only; models are ordinary readable files, like a curl download.
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: staged.path)
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: dest)
            }
        }
    }
}

/// One URLSession download with byte progress and cancellation. The finished file is moved to `to`
/// inside the delegate callback, because URLSession deletes its temporary file right after.
final class FileFetcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private var target: URL?
    private var name = ""
    private var failure: Error?

    init(progress: @escaping @Sendable (Int64) -> Void) { self.progress = progress }

    func fetch(_ url: URL, to target: URL, name: String) async throws {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.lock()
                self.continuation = c
                self.target = target
                self.name = name
                let t = session.downloadTask(with: url)
                self.task = t
                lock.unlock()
                t.resume()
            }
        } onCancel: {
            lock.lock(); let t = task; lock.unlock()
            t?.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock(); defer { lock.unlock() }
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            failure = ModelInstallError.http(http.statusCode, name)
            return
        }
        guard let target else { return }
        do { try FileManager.default.moveItem(at: location, to: target) } catch { failure = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let c = continuation
        continuation = nil
        let err = error ?? failure
        lock.unlock()
        if let err {
            let cancelled = (err as? URLError)?.code == .cancelled
            c?.resume(throwing: cancelled ? CancellationError() : err)
        } else {
            c?.resume()
        }
    }
}

// MARK: - Views

/// The card at the top of Recordings (and Settings) while models are missing or downloading.
struct ModelSetupCard: View {
    @ObservedObject var models: ModelDownloader

    /// Shown while a required model is missing, and while any download runs or has just failed
    /// (a failed Translate download must still say why).
    private var visible: Bool { models.needsRequired || models.state != .idle }

    var body: some View {
        if visible {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.brandAccent)
                VStack(alignment: .leading, spacing: 8) {
                    Text(models.isDownloading ? "Downloading the models" : "Download the speech models")
                        .font(.headline)
                    content
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch models.state {
        case .downloading:
            ProgressView(value: Double(models.received), total: Double(max(models.total, 1)))
                .tint(Color.brandAccent)
            HStack {
                Text("\(models.current) · \(ModelCatalog.size(models.received)) of \(ModelCatalog.size(models.total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Cancel") { models.cancel() }
                    .controlSize(.small)
            }
        case let .failed(message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            downloadButton(title: "Try Again", groups: models.lastGroups)
        case .idle:
            Text("Earshot turns speech into text with models that run on this Mac. Download them once "
                 + "and nothing needs the internet after that. They are saved in ~/Models.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            downloadButton(title: "Download (\(ModelCatalog.size(ModelCatalog.totalBytes(models.missingRequired))))",
                           groups: ModelCatalog.required)
        }
    }

    private func downloadButton(title: String, groups: Set<ModelGroup>) -> some View {
        Button(title) { models.download(groups) }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandAccent)
    }
}
