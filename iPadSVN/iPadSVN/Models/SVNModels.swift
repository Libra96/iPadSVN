import Foundation

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case browse, changes, history, settings

    var id: String { rawValue }
}

enum GalleryTab: String, CaseIterable, Identifiable {
    case repos, settings

    var id: String { rawValue }
}

enum SVNFileStatus: String, Codable, CaseIterable {
    case modified = "M"
    case added = "A"
    case deleted = "D"

    var label: String {
        switch self {
        case .modified: return "修改"
        case .added: return "新增"
        case .deleted: return "删除"
        }
    }
}

enum SVNFileKind: String, Codable {
    case folder, file
}

struct SVNRepository: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var url: String
    var revision: Int
    var lastSyncDescription: String
    var localPath: String

    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        revision: Int,
        lastSyncDescription: String,
        localPath: String
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.revision = revision
        self.lastSyncDescription = lastSyncDescription
        self.localPath = localPath
    }
}

struct SVNFileNode: Identifiable, Codable, Equatable {
    var id: String { path.isEmpty ? name : path }
    var name: String
    var path: String
    var kind: SVNFileKind
    var ext: String?
    var status: SVNFileStatus?
    var sizeDescription: String?
    var modifiedDescription: String?
    var children: [SVNFileNode]?
    var diffLines: [DiffLine]?

    var isFolder: Bool { kind == .folder }

    static func folder(_ name: String, path: String, children: [SVNFileNode]) -> SVNFileNode {
        SVNFileNode(
            name: name,
            path: path,
            kind: .folder,
            ext: nil,
            status: nil,
            sizeDescription: nil,
            modifiedDescription: nil,
            children: children,
            diffLines: nil
        )
    }

    static func file(
        _ name: String,
        path: String,
        ext: String,
        status: SVNFileStatus? = nil,
        size: String? = nil,
        modified: String? = nil,
        diff: [DiffLine]? = nil
    ) -> SVNFileNode {
        SVNFileNode(
            name: name,
            path: path,
            kind: .file,
            ext: ext,
            status: status,
            sizeDescription: size,
            modifiedDescription: modified,
            children: nil,
            diffLines: diff
        )
    }
}

struct DiffLine: Identifiable, Codable, Equatable {
    enum LineType: String, Codable {
        case context, add, delete
    }

    var id: Int { lineNumber }
    let lineNumber: Int
    let type: LineType
    let text: String
}

struct SVNChange: Identifiable, Equatable {
    var id: String { node.path }
    let node: SVNFileNode
}

struct CommitRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let revision: Int
    let message: String
    let author: String
    let dateDescription: String

    init(revision: Int, message: String, author: String, dateDescription: String) {
        self.id = UUID()
        self.revision = revision
        self.message = message
        self.author = author
        self.dateDescription = dateDescription
    }
}

struct CommitRequest {
    let repositoryID: UUID
    let message: String
    let paths: [String]
}

enum SVNError: LocalizedError {
    case repositoryNotFound
    case pathNotFound
    case emptyCommitMessage
    case noChangesSelected
    case notImplemented
    case operationFailed(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .repositoryNotFound: return "找不到仓库"
        case .pathNotFound: return "找不到路径"
        case .emptyCommitMessage: return "请填写提交说明"
        case .noChangesSelected: return "请至少选择一个文件"
        case .notImplemented: return "libsvn 未链接，请先完成云编译"
        case .operationFailed(let msg): return msg
        case .invalidURL: return "SVN 地址无效"
        }
    }
}
