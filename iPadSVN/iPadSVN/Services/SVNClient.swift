import Foundation

protocol SVNClient: Sendable {
    func listRepositories() async throws -> [SVNRepository]
    func checkout(url: String, name: String, username: String?, password: String?) async throws -> SVNRepository
    func update(repositoryID: UUID) async throws -> Int
    func fileTree(repositoryID: UUID) async throws -> SVNFileNode
    func changes(repositoryID: UUID) async throws -> [SVNChange]
    func history(repositoryID: UUID) async throws -> [CommitRecord]
    func commit(_ request: CommitRequest) async throws -> Int
    func revert(repositoryID: UUID, path: String) async throws
}

extension SVNClient {
    func collectChanges(in node: SVNFileNode, prefix: String = "") -> [SVNChange] {
        switch node.kind {
        case .file:
            if let status = node.status {
                return [SVNChange(node: node)]
            }
            return []
        case .folder:
            guard let children = node.children else { return [] }
            return children.flatMap { child in
                let childPath = prefix.isEmpty ? child.name : "\(prefix)/\(child.name)"
                var updated = child
                updated.path = childPath
                return collectChanges(in: updated, prefix: childPath)
            }
        }
    }

    func node(at pathComponents: [String], in root: SVNFileNode) -> SVNFileNode? {
        guard !pathComponents.isEmpty else { return root }
        var current = root
        for component in pathComponents {
            guard let children = current.children,
                  let next = children.first(where: { $0.name == component }) else {
                return nil
            }
            current = next
        }
        return current
    }

    func folderHasChanges(_ node: SVNFileNode) -> Bool {
        if node.kind == .file { return node.status != nil }
        guard let children = node.children else { return false }
        return children.contains(where: folderHasChanges)
    }
}
