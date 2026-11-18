// Files that hold what you said, or what you did, are readable by you only (ADR-2611072100 A3).
// Foundation and Darwin only.
import Darwin
import Foundation

enum PrivateFiles {
    /// Appends `line` to the file at `url`, creating it with mode 600 and tightening an existing one to 600.
    /// A symlink in its place is refused rather than followed.
    static func appendLine(_ line: String, to url: URL) {
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        fchmod(fd, 0o600)
        writeAll(fd, Data(line.utf8))
    }

    /// Replaces the file at `url` with `data` in one step. The file is 600 from the moment it exists, and its
    /// folder is created, or tightened, to 700 (unless `tightenFolder` is false: the recordings folder is the user's).
    @discardableResult
    static func writeAtomically(_ data: Data, to url: URL, tightenFolder: Bool = true) -> Bool {
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            return false
        }
        if tightenFolder { chmod(dir.path, 0o700) }
        let temp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        let ok = writeAll(fd, data) && fsync(fd) == 0
        close(fd)
        guard ok, rename(temp.path, url.path) == 0 else {
            unlink(temp.path)
            return false
        }
        return true
    }

    @discardableResult
    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            guard var p = raw.baseAddress else { return true }
            var left = raw.count
            while left > 0 {
                let n = write(fd, p, left)
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                left -= n
                p += n
            }
            return true
        }
    }
}
