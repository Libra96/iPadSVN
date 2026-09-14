import Foundation

/// libsvn 真实客户端占位。
/// `libsvn.xcframework` 编译验证通过后，在此实现 Checkout / Update / Commit / Status。
final class LibSvnClient: SVNClient, @unchecked Sendable {
    func listRepositories() async throws -> [SVNRepository] { throw SVNError.notImplemented }
    func checkout(url: String, name: String, username: String?, password: String?) async throws -> SVNRepository { throw SVNError.notImplemented }
    func update(repositoryID: UUID) async throws -> Int { throw SVNError.notImplemented }
    func fileTree(repositoryID: UUID) async throws -> SVNFileNode { throw SVNError.notImplemented }
    func changes(repositoryID: UUID) async throws -> [SVNChange] { throw SVNError.notImplemented }
    func history(repositoryID: UUID) async throws -> [CommitRecord] { throw SVNError.notImplemented }
    func commit(_ request: CommitRequest) async throws -> Int { throw SVNError.notImplemented }
    func revert(repositoryID: UUID, path: String) async throws { throw SVNError.notImplemented }
}
