import Foundation

final class MockSVNClient: SVNClient, @unchecked Sendable {
    private var repositories: [UUID: SVNRepository] = [:]
    private var trees: [UUID: SVNFileNode] = [:]
    private var histories: [UUID: [CommitRecord]] = [:]

    init() {
        let demos = Self.demoRepositories()
        for demo in demos {
            repositories[demo.repo.id] = demo.repo
            trees[demo.repo.id] = demo.tree
            histories[demo.repo.id] = demo.history
        }
    }

    func listRepositories() async throws -> [SVNRepository] {
        repositories.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func checkout(url: String, name: String, username: String?, password: String?) async throws -> SVNRepository {
        let repo = SVNRepository(
            name: name,
            url: url,
            revision: 1,
            lastSyncDescription: "刚刚",
            localPath: "~/Documents/\(name)"
        )
        repositories[repo.id] = repo
        trees[repo.id] = .folder(name, path: "", children: [])
        histories[repo.id] = []
        return repo
    }

    func update(repositoryID: UUID) async throws -> Int {
        guard var repo = repositories[repositoryID] else { throw SVNError.repositoryNotFound }
        repo.lastSyncDescription = "刚刚"
        repositories[repositoryID] = repo
        return repo.revision
    }

    func fileTree(repositoryID: UUID) async throws -> SVNFileNode {
        guard let tree = trees[repositoryID] else { throw SVNError.repositoryNotFound }
        return tree
    }

    func changes(repositoryID: UUID) async throws -> [SVNChange] {
        let tree = try await fileTree(repositoryID: repositoryID)
        return collectChanges(in: tree)
    }

    func history(repositoryID: UUID) async throws -> [CommitRecord] {
        guard let history = histories[repositoryID] else { throw SVNError.repositoryNotFound }
        return history
    }

    func commit(_ request: CommitRequest) async throws -> Int {
        guard !request.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SVNError.emptyCommitMessage
        }
        guard !request.paths.isEmpty else { throw SVNError.noChangesSelected }
        guard var repo = repositories[request.repositoryID] else { throw SVNError.repositoryNotFound }
        guard var tree = trees[request.repositoryID] else { throw SVNError.repositoryNotFound }

        tree = clearStatus(in: tree, paths: Set(request.paths))
        trees[request.repositoryID] = tree

        repo.revision += 1
        repo.lastSyncDescription = "刚刚"
        repositories[request.repositoryID] = repo

        var history = histories[request.repositoryID] ?? []
        history.insert(
            CommitRecord(
                revision: repo.revision,
                message: request.message,
                author: "你",
                dateDescription: "刚刚"
            ),
            at: 0
        )
        histories[request.repositoryID] = history
        return repo.revision
    }

    func revert(repositoryID: UUID, path: String) async throws {
        guard var tree = trees[repositoryID] else { throw SVNError.repositoryNotFound }
        tree = clearStatus(in: tree, paths: [path])
        trees[repositoryID] = tree
    }

    private func clearStatus(in node: SVNFileNode, paths: Set<String>) -> SVNFileNode {
        var updated = node
        if updated.kind == .file, paths.contains(updated.path) {
            updated.status = nil
            updated.diffLines = nil
        }
        if let children = updated.children {
            updated.children = children.map { clearStatus(in: $0, paths: paths) }
        }
        return updated
    }

    private static func demoRepositories() -> [(repo: SVNRepository, tree: SVNFileNode, history: [CommitRecord])] {
        let mobileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let backendID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let designID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

        let mobileTree: SVNFileNode = .folder("mobile-app", path: "", children: [
            .folder("src", path: "src", children: [
                .folder("components", path: "src/components", children: [
                    .file("LoginView.swift", path: "src/components/LoginView.swift", ext: "swift", status: .modified, size: "4.2 KB", modified: "今天 14:32", diff: [
                        .init(lineNumber: 12, type: .context, text: "  var body: some View {"),
                        .init(lineNumber: 13, type: .delete, text: "- Text(\"登录\")"),
                        .init(lineNumber: 14, type: .add, text: "+ Text(\"欢迎回来\")"),
                        .init(lineNumber: 15, type: .add, text: "+     .font(.title2.bold())"),
                        .init(lineNumber: 16, type: .context, text: "  Button(\"Sign In\") { … }")
                    ]),
                    .file("HomeView.swift", path: "src/components/HomeView.swift", ext: "swift", size: "2.8 KB")
                ]),
                .folder("services", path: "src/services", children: [
                    .file("AuthService.swift", path: "src/services/AuthService.swift", ext: "swift", status: .added, size: "1.1 KB", diff: [
                        .init(lineNumber: 1, type: .add, text: "+ import Foundation"),
                        .init(lineNumber: 2, type: .add, text: "+ final class AuthService {"),
                        .init(lineNumber: 3, type: .add, text: "+     static let shared = AuthService()"),
                        .init(lineNumber: 4, type: .add, text: "+ }")
                    ])
                ]),
                .folder("legacy", path: "src/legacy", children: [
                    .file("LegacyAuth.m", path: "src/legacy/LegacyAuth.m", ext: "objc", status: .deleted, size: "890 B", diff: [
                        .init(lineNumber: 1, type: .delete, text: "- // Legacy authentication"),
                        .init(lineNumber: 2, type: .delete, text: "- @implementation LegacyAuth")
                    ])
                ])
            ]),
            .folder("Resources", path: "Resources", children: [
                .file("AppConfig.plist", path: "Resources/AppConfig.plist", ext: "plist", status: .modified, size: "620 B", diff: [
                    .init(lineNumber: 4, type: .context, text: "  <key>Environment</key>"),
                    .init(lineNumber: 5, type: .delete, text: "- <string>dev</string>"),
                    .init(lineNumber: 6, type: .add, text: "+ <string>prod</string>")
                ]),
                .folder("Assets.xcassets", path: "Resources/Assets.xcassets", children: [])
            ]),
            .folder("Tests", path: "Tests", children: [
                .file("LoginTests.swift", path: "Tests/LoginTests.swift", ext: "swift", size: "1.4 KB")
            ]),
            .file("README.md", path: "README.md", ext: "md", size: "3.1 KB")
        ])

        let backendTree: SVNFileNode = .folder("backend-api", path: "", children: [
            .folder("api", path: "api", children: [
                .folder("routes", path: "api/routes", children: [
                    .file("users.go", path: "api/routes/users.go", ext: "go", status: .modified, size: "2.1 KB", modified: "昨天", diff: [
                        .init(lineNumber: 8, type: .context, text: "func GetUsers(w http.ResponseWriter, r *http.Request) {"),
                        .init(lineNumber: 9, type: .add, text: "+     limit := 100"),
                        .init(lineNumber: 10, type: .context, text: "}")
                    ])
                ]),
                .folder("middleware", path: "api/middleware", children: [
                    .file("auth.go", path: "api/middleware/auth.go", ext: "go", size: "980 B")
                ])
            ]),
            .folder("config", path: "config", children: [
                .file("app.json", path: "config/app.json", ext: "json", size: "340 B")
            ]),
            .file("go.mod", path: "go.mod", ext: "md", size: "120 B")
        ])

        let designTree: SVNFileNode = .folder("design-system", path: "", children: [
            .folder("tokens", path: "tokens", children: [
                .file("colors.json", path: "tokens/colors.json", ext: "json", status: .modified, size: "560 B", diff: [
                    .init(lineNumber: 2, type: .context, text: "  \"primary\": "),
                    .init(lineNumber: 3, type: .delete, text: "- \"#6366f1\""),
                    .init(lineNumber: 4, type: .add, text: "+ \"#007AFF\"")
                ]),
                .file("spacing.json", path: "tokens/spacing.json", ext: "json", size: "420 B")
            ]),
            .folder("components", path: "components", children: [
                .file("Button.md", path: "components/Button.md", ext: "md", size: "1.8 KB")
            ])
        ])

        return [
            (
                SVNRepository(id: mobileID, name: "mobile-app", url: "svn.company.com/mobile/trunk", revision: 1284, lastSyncDescription: "2 分钟前", localPath: "~/Documents/mobile-app"),
                mobileTree,
                [
                    CommitRecord(revision: 1284, message: "fix: 修复登录超时", author: "你", dateDescription: "2 分钟前"),
                    CommitRecord(revision: 1283, message: "feat: 新增 AuthService", author: "你", dateDescription: "昨天"),
                    CommitRecord(revision: 1282, message: "chore: 更新依赖", author: "张三", dateDescription: "3 天前")
                ]
            ),
            (
                SVNRepository(id: backendID, name: "backend-api", url: "svn.company.com/backend/trunk", revision: 892, lastSyncDescription: "1 小时前", localPath: "~/Documents/backend-api"),
                backendTree,
                [
                    CommitRecord(revision: 892, message: "fix: API 限流逻辑", author: "李四", dateDescription: "1 小时前"),
                    CommitRecord(revision: 891, message: "feat: /users 端点", author: "你", dateDescription: "2 天前")
                ]
            ),
            (
                SVNRepository(id: designID, name: "design-system", url: "svn.company.com/design/branches/v2", revision: 456, lastSyncDescription: "今天 09:12", localPath: "~/Documents/design-system"),
                designTree,
                [
                    CommitRecord(revision: 456, message: "style: 更新主色 token", author: "王五", dateDescription: "今天")
                ]
            )
        ]
    }
}
