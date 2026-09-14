import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var repositories: [SVNRepository] = []
    @Published var selectedRepositoryID: UUID?
    @Published var galleryTab: GalleryTab = .repos
    @Published var workspaceTab: WorkspaceTab = .browse
    @Published var browsePath: [String] = []
    @Published var browseSearchText = ""
    @Published var browseOnlyChanges = false
    @Published var selectedFilePath: String?
    @Published var expandedChangePath: String?
    @Published var isSyncing = false
    @Published var toastMessage: String?
    @Published var showCommitSheet = false
    @Published var showRepoSwitcher = false
    @Published var showCheckoutSheet = false
    @Published var commitMessage = ""
    @Published var selectedCommitPaths: Set<String> = []

    @Published private(set) var fileTree: SVNFileNode?
    @Published private(set) var changes: [SVNChange] = []
    @Published private(set) var history: [CommitRecord] = []

    private let client: SVNClient

    var isInWorkspace: Bool { selectedRepositoryID != nil }

    var selectedRepository: SVNRepository? {
        guard let id = selectedRepositoryID else { return nil }
        return repositories.first { $0.id == id }
    }

    var selectedFileNode: SVNFileNode? {
        guard let path = selectedFilePath, let tree = fileTree else { return nil }
        return client.node(at: path.split(separator: "/").map(String.init), in: tree)
    }

    init(client: SVNClient = MockSVNClient()) {
        self.client = client
    }

    func bootstrap() async {
        await reloadRepositories()
    }

    func reloadRepositories() async {
        do {
            repositories = try await client.listRepositories()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func enterRepository(_ repo: SVNRepository) async {
        selectedRepositoryID = repo.id
        workspaceTab = .browse
        browsePath = []
        browseSearchText = ""
        browseOnlyChanges = false
        selectedFilePath = nil
        expandedChangePath = nil
        await refreshWorkspace()
    }

    func leaveWorkspace() {
        selectedRepositoryID = nil
        fileTree = nil
        changes = []
        history = []
        selectedFilePath = nil
        expandedChangePath = nil
        galleryTab = .repos
    }

    func refreshWorkspace() async {
        guard let id = selectedRepositoryID else { return }
        do {
            async let treeTask = client.fileTree(repositoryID: id)
            async let changesTask = client.changes(repositoryID: id)
            async let historyTask = client.history(repositoryID: id)
            fileTree = try await treeTask
            changes = try await changesTask
            history = try await historyTask
            await reloadRepositories()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func updateRepository() async {
        guard let id = selectedRepositoryID else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            _ = try await client.update(repositoryID: id)
            await refreshWorkspace()
            if let name = selectedRepository?.name {
                showToast("✓ \(name) 已更新")
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func openCommitSheet() {
        commitMessage = selectedRepository.map { "feat: 更新 \($0.name)" } ?? ""
        selectedCommitPaths = Set(changes.map(\.id))
        showCommitSheet = true
    }

    func submitCommit() async {
        guard let id = selectedRepositoryID else { return }
        let request = CommitRequest(
            repositoryID: id,
            message: commitMessage,
            paths: Array(selectedCommitPaths)
        )
        do {
            let rev = try await client.commit(request)
            showCommitSheet = false
            selectedFilePath = nil
            expandedChangePath = nil
            await refreshWorkspace()
            showToast("✓ 已提交到 r\(rev)")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func revertSelectedFile() async {
        guard let id = selectedRepositoryID, let path = selectedFilePath else { return }
        do {
            try await client.revert(repositoryID: id, path: path)
            selectedFilePath = nil
            await refreshWorkspace()
            showToast("已还原文件")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func switchRepository(_ repo: SVNRepository) async {
        showRepoSwitcher = false
        guard repo.id != selectedRepositoryID else { return }
        await enterRepository(repo)
        showToast("已切换到 \(repo.name)")
    }

    func checkoutRepository(url: String, name: String) async {
        do {
            let repo = try await client.checkout(url: url, name: name, username: nil, password: nil)
            await reloadRepositories()
            showCheckoutSheet = false
            await enterRepository(repo)
            showToast("✓ 已 Checkout \(repo.name)")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func currentBrowseNode() -> SVNFileNode? {
        guard let tree = fileTree else { return nil }
        if browsePath.isEmpty { return tree }
        return client.node(at: browsePath, in: tree)
    }

    func browseEntries() -> [SVNFileNode] {
        guard let node = currentBrowseNode(), let children = node.children else { return [] }
        var entries = children.map { child -> SVNFileNode in
            var item = child
            item.path = browsePath.isEmpty ? child.name : browsePath.joined(separator: "/") + "/" + child.name
            return item
        }

        let query = browseSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            entries = entries.filter { $0.name.lowercased().contains(query) }
        }
        if browseOnlyChanges {
            entries = entries.filter { entry in
                entry.kind == .file ? entry.status != nil : client.folderHasChanges(entry)
            }
        }

        return entries.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .folder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
    }

    func clientFolderHasChanges(_ node: SVNFileNode) -> Bool {
        client.folderHasChanges(node)
    }
}
