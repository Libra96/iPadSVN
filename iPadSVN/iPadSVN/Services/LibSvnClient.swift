import Foundation

final class LibSvnClient: SVNClient, @unchecked Sendable {
    private let store = RepositoryStore.shared
    private let credentials = CredentialsStore.shared
    private let fm = FileManager.default

    init() {
        SVNBridgeAPI.initialize()
    }

    func listRepositories() async throws -> [SVNRepository] {
        store.load().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func checkout(url: String, name: String, username: String?, password: String?) async throws -> SVNRepository {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { throw SVNError.invalidURL }

        let safeName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = safeName.isEmpty ? defaultName(from: trimmedURL) : safeName
        let localURL = store.localURL(for: folderName)

        if fm.fileExists(atPath: localURL.path) {
            try fm.removeItem(at: localURL)
        }

        let rev = try await runOnBackground {
            try SVNBridgeAPI.checkout(
                url: trimmedURL,
                localPath: localURL.path,
                username: username,
                password: password
            )
        }

        let repo = SVNRepository(
            name: folderName,
            url: trimmedURL,
            revision: Int(rev),
            lastSyncDescription: "刚刚",
            localPath: localURL.path
        )

        if let username, let password, !username.isEmpty {
            credentials.save(username: username, password: password, for: repo.id)
        }

        var all = store.load()
        all.removeAll { $0.localPath == repo.localPath }
        all.append(repo)
        store.save(all)
        return repo
    }

    func update(repositoryID: UUID) async throws -> Int {
        let repo = try requireRepo(repositoryID)
        let creds = credentials.load(for: repositoryID)
        let rev = try await runOnBackground {
            try SVNBridgeAPI.update(
                wcPath: repo.localPath,
                username: creds?.username,
                password: creds?.password
            )
        }
        try await persistRevision(repositoryID: repositoryID, revision: Int(rev))
        return Int(rev)
    }

    func fileTree(repositoryID: UUID) async throws -> SVNFileNode {
        let repo = try requireRepo(repositoryID)
        let statusMap = try await statusMap(for: repo)
        guard fm.fileExists(atPath: repo.localPath) else {
            throw SVNError.pathNotFound
        }
        return buildTree(at: repo.localPath, relativePrefix: "", repoName: repo.name, statusMap: statusMap)
    }

    func changes(repositoryID: UUID) async throws -> [SVNChange] {
        let repo = try requireRepo(repositoryID)
        let statusMap = try await statusMap(for: repo)
        return statusMap.compactMap { path, status in
            guard let svnStatus = mapStatus(status) else { return nil }
            let fullPath = (path as NSString).standardizingPath
            let name = (fullPath as NSString).lastPathComponent
            let ext = (name as NSString).pathExtension.lowercased()
            return SVNChange(
                node: .file(
                    name,
                    path: path,
                    ext: ext.isEmpty ? "txt" : ext,
                    status: svnStatus,
                    size: fileSize(at: repo.localPath, relative: path),
                    modified: nil,
                    diff: nil
                )
            )
        }.sorted { $0.node.path.localizedCaseInsensitiveCompare($1.node.path) == .orderedAscending }
    }

    func history(repositoryID: UUID) async throws -> [CommitRecord] {
        let repo = try requireRepo(repositoryID)
        let creds = credentials.load(for: repositoryID)
        let json = try await runOnBackground {
            try SVNBridgeAPI.logJSON(
                wcPath: repo.localPath,
                username: creds?.username,
                password: creds?.password,
                limit: 30
            )
        }
        let rows = try JSONDecoder().decode([LogRow].self, from: Data(json.utf8))
        return rows.map {
            CommitRecord(
                revision: $0.revision,
                message: $0.message,
                author: $0.author,
                dateDescription: $0.date
            )
        }
    }

    func commit(_ request: CommitRequest) async throws -> Int {
        guard !request.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SVNError.emptyCommitMessage
        }
        guard !request.paths.isEmpty else { throw SVNError.noChangesSelected }

        let repo = try requireRepo(request.repositoryID)
        let creds = credentials.load(for: request.repositoryID)
        let rev = try await runOnBackground {
            try SVNBridgeAPI.commit(
                wcPath: repo.localPath,
                username: creds?.username,
                password: creds?.password,
                message: request.message,
                paths: request.paths
            )
        }
        try await persistRevision(repositoryID: request.repositoryID, revision: Int(rev))
        return Int(rev)
    }

    func revert(repositoryID: UUID, path: String) async throws {
        let repo = try requireRepo(repositoryID)
        let creds = credentials.load(for: repositoryID)
        try await runOnBackground {
            try SVNBridgeAPI.revert(
                wcPath: repo.localPath,
                username: creds?.username,
                password: creds?.password,
                relativePath: path
            )
        }
    }

    func diffLines(repositoryID: UUID, relativePath: String) async throws -> [DiffLine] {
        let repo = try requireRepo(repositoryID)
        let creds = credentials.load(for: repositoryID)
        let text = try await runOnBackground {
            try SVNBridgeAPI.diffText(
                wcPath: repo.localPath,
                username: creds?.username,
                password: creds?.password,
                relativePath: relativePath
            )
        }
        return parseDiff(text)
    }

    // MARK: - Helpers

    private struct LogRow: Decodable {
        let revision: Int
        let author: String
        let date: String
        let message: String
    }

    private struct StatusRow: Decodable {
        let path: String
        let status: String
    }

    private func requireRepo(_ id: UUID) throws -> SVNRepository {
        guard let repo = store.load().first(where: { $0.id == id }) else {
            throw SVNError.repositoryNotFound
        }
        return repo
    }

    private func persistRevision(repositoryID: UUID, revision: Int) async throws {
        var all = store.load()
        guard let idx = all.firstIndex(where: { $0.id == repositoryID }) else { return }
        all[idx].revision = revision
        all[idx].lastSyncDescription = "刚刚"
        store.save(all)
    }

    private func statusMap(for repo: SVNRepository) async throws -> [String: String] {
        let creds = credentials.load(for: repo.id)
        let json = try await runOnBackground {
            try SVNBridgeAPI.statusJSON(
                wcPath: repo.localPath,
                username: creds?.username,
                password: creds?.password
            )
        }
        let rows = try JSONDecoder().decode([StatusRow].self, from: Data(json.utf8))
        var map: [String: String] = [:]
        for row in rows {
            map[row.path] = row.status
        }
        return map
    }

    private func buildTree(
        at absolutePath: String,
        relativePrefix: String,
        repoName: String,
        statusMap: [String: String]
    ) -> SVNFileNode {
        let url = URL(fileURLWithPath: absolutePath)
        let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        let nodes: [SVNFileNode] = children
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { childURL in
                let name = childURL.lastPathComponent
                if name == ".svn" { return nil }
                let rel = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"
                var isDir: ObjCBool = false
                fm.fileExists(atPath: childURL.path, isDirectory: &isDir)
                if isDir.boolValue {
                    return buildTree(at: childURL.path, relativePrefix: rel, repoName: repoName, statusMap: statusMap)
                }
                let ext = childURL.pathExtension.lowercased()
                let status = mapStatus(statusMap[rel])
                let size = (try? childURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
                return .file(name, path: rel, ext: ext.isEmpty ? "txt" : ext, status: status, size: size)
            }
        if relativePrefix.isEmpty {
            return .folder(repoName, path: "", children: nodes)
        }
        let folderName = (relativePrefix as NSString).lastPathComponent
        return .folder(folderName, path: relativePrefix, children: nodes)
    }

    private func mapStatus(_ raw: String?) -> SVNFileStatus? {
        switch raw {
        case "modified": return .modified
        case "added": return .added
        case "deleted": return .deleted
        case "replaced": return .modified
        default: return nil
        }
    }

    private func fileSize(at wc: String, relative: String) -> String? {
        let path = (wc as NSString).appendingPathComponent(relative)
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }

    private func defaultName(from url: String) -> String {
        URL(string: url)?.lastPathComponent ?? "repo-\(Int(Date().timeIntervalSince1970))"
    }

    private func runOnBackground<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func parseDiff(_ text: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        var lineNumber = 1
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let type: DiffLine.LineType
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                type = .add
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                type = .delete
            } else {
                type = .context
            }
            lines.append(DiffLine(lineNumber: lineNumber, type: type, text: line))
            lineNumber += 1
        }
        return lines
    }
}
