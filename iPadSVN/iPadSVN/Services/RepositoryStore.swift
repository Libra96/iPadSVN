import Foundation

final class RepositoryStore {
    static let shared = RepositoryStore()

    private let fileURL: URL
    private let fm = FileManager.default

    private init() {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("iPadSVN", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("repositories.json")
    }

    var workingCopiesRoot: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let root = docs.appendingPathComponent("WorkingCopies", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func load() -> [SVNRepository] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([SVNRepository].self, from: data)) ?? []
    }

    func save(_ repos: [SVNRepository]) {
        guard let data = try? JSONEncoder().encode(repos) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func localURL(for name: String) -> URL {
        workingCopiesRoot.appendingPathComponent(name, isDirectory: true)
    }
}
