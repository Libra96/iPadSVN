import SwiftUI

struct BrowseView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            browseToolbar
            breadcrumb
            fileList
        }
        .overlay(alignment: .bottom) {
            if let node = store.selectedFileNode, store.selectedFilePath != nil {
                FilePreviewPanel(node: node)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: store.selectedFilePath)
    }

    private var browseToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.inkTertiary)
                TextField("搜索当前目录…", text: $store.browseSearchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(AppTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                store.browseOnlyChanges.toggle()
            } label: {
                Text("仅变更")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(store.browseOnlyChanges ? AppTheme.modifiedBackground : AppTheme.surface)
                    .foregroundStyle(store.browseOnlyChanges ? Color(red: 0.788, green: 0.204, blue: 0.0) : AppTheme.inkSecondary)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(store.browseOnlyChanges ? AppTheme.modified.opacity(0.35) : AppTheme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.line).frame(height: 1) }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if let repo = store.selectedRepository {
                    breadcrumbButton(title: repo.name, path: [])
                }
                ForEach(Array(store.browsePath.enumerated()), id: \.offset) { index, segment in
                    Text("›")
                        .foregroundStyle(AppTheme.inkTertiary)
                        .font(.system(size: 12))
                    breadcrumbButton(
                        title: segment,
                        path: Array(store.browsePath.prefix(index + 1)),
                        isLast: index == store.browsePath.count - 1
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(AppTheme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.line).frame(height: 1) }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                let entries = store.browseEntries()
                let folders = entries.filter(\.isFolder)
                let files = entries.filter { !$0.isFolder }

                if entries.isEmpty {
                    ContentUnavailableView(
                        store.browseSearchText.isEmpty && !store.browseOnlyChanges ? "空文件夹" : "没有匹配的文件",
                        systemImage: "folder"
                    )
                    .padding(.top, 48)
                } else {
                    if !folders.isEmpty {
                        section(title: "文件夹", items: folders)
                    }
                    if !files.isEmpty {
                        section(title: "文件", items: files)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, store.selectedFilePath == nil ? 120 : 280)
        }
    }

    @ViewBuilder
    private func section(title: String, items: [SVNFileNode]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.inkTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(items) { item in
                    FileRowView(
                        item: item,
                        isSelected: store.selectedFilePath == item.path,
                        hasChangesInside: item.isFolder && store.clientFolderHasChanges(item)
                    ) {
                        handleTap(on: item)
                    }
                    if item.id != items.last?.id {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            )
        }
    }

    private func breadcrumbButton(title: String, path: [String], isLast: Bool = false) -> some View {
        Button {
            guard !isLast else { return }
            store.browsePath = path
            store.selectedFilePath = nil
        } label: {
            Text(title)
                .font(.system(size: 14, weight: isLast ? .semibold : .medium))
                .foregroundStyle(isLast ? AppTheme.ink : AppTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(isLast)
    }

    private func handleTap(on item: SVNFileNode) {
        if item.isFolder {
            store.browsePath.append(item.name)
            store.selectedFilePath = nil
        } else {
            store.selectedFilePath = item.path
        }
    }
}

private struct FileRowView: View {
    let item: SVNFileNode
    let isSelected: Bool
    let hasChangesInside: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                FileIconView(ext: item.ext, isFolder: item.isFolder)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.inkTertiary)
                }
                Spacer()
                if hasChangesInside {
                    Circle().fill(AppTheme.modified).frame(width: 7, height: 7)
                }
                if let status = item.status {
                    StatusTag(status: status)
                }
                if item.isFolder {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.inkTertiary)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: AppTheme.touch)
            .background(isSelected ? AppTheme.accentSoft : .clear)
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if item.isFolder {
            let count = item.children?.count ?? 0
            return "\(count) 项"
        }
        return [item.sizeDescription, item.modifiedDescription]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

struct FileIconView: View {
    let ext: String?
    let isFolder: Bool

    var body: some View {
        Group {
            if isFolder {
                Image(systemName: "folder.fill")
            } else {
                Image(systemName: iconName)
            }
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(.white)
        .frame(width: 36, height: 36)
        .background(iconBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var iconName: String {
        switch ext {
        case "swift": return "chevron.left.forwardslash.chevron.right"
        case "plist", "json", "md": return "doc.text"
        default: return "doc"
        }
    }

    private var iconBackground: LinearGradient {
        if isFolder {
            return LinearGradient(colors: [AppTheme.accent.opacity(0.85), AppTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        switch ext {
        case "swift":
            return LinearGradient(colors: [Color.orange, Color.red.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "plist":
            return LinearGradient(colors: [Color.gray, Color.gray.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "objc":
            return LinearGradient(colors: [Color.purple, Color.purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "json":
            return LinearGradient(colors: [Color.green, Color.green.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "go":
            return LinearGradient(colors: [Color.teal, AppTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [Color.cyan, AppTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
