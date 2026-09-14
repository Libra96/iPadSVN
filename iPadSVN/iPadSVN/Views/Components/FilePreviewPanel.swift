import SwiftUI

struct FilePreviewPanel: View {
    @EnvironmentObject private var store: AppStore
    let node: SVNFileNode

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AppTheme.line)
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            HStack(spacing: 12) {
                FileIconView(ext: node.ext, isFolder: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    if let repo = store.selectedRepository {
                        Text("\(repo.name)/\(node.path)")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.inkTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let status = node.status {
                    StatusTag(status: status)
                }
                Button {
                    store.selectedFilePath = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.inkSecondary)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            HStack(spacing: 16) {
                metaItem(node.sizeDescription ?? "—")
                if let repo = store.selectedRepository {
                    metaItem("r\(repo.revision)")
                }
                metaItem(node.status?.label ?? "无本地变更")
            }
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.line).frame(height: 1) }

            ScrollView {
                if let lines = node.diffLines, !lines.isEmpty {
                    DiffLinesView(lines: lines)
                } else {
                    Text("（无文本预览）")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppTheme.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
            .frame(maxHeight: 180)
            .background(AppTheme.surfaceSecondary)

            HStack(spacing: 8) {
                if node.status != nil {
                    Button("还原此文件") {
                        Task { await store.revertSelectedFile() }
                    }
                    .buttonStyle(SecondaryPanelButtonStyle())

                    Button("查看变更 Diff") {
                        store.selectedFilePath = nil
                        store.workspaceTab = .changes
                        store.expandedChangePath = node.path
                    }
                    .buttonStyle(PrimaryPanelButtonStyle())
                } else {
                    Button("关闭") {
                        store.selectedFilePath = nil
                    }
                    .buttonStyle(PrimaryPanelButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 20, y: -4)
        .padding(.horizontal, 0)
    }

    private func metaItem(_ text: String) -> some View {
        Text(text)
    }
}

struct SecondaryPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.line))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct PrimaryPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(AppTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
