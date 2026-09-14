import SwiftUI

struct RailView: View {
    enum Mode {
        case gallery(GalleryTab)
        case workspace(WorkspaceTab, changeCount: Int)
    }

    let mode: Mode
    let onSelectGallery: (GalleryTab) -> Void
    let onSelectWorkspace: (WorkspaceTab) -> Void

    var body: some View {
        VStack(spacing: 4) {
            switch mode {
            case .gallery(let tab):
                railButton(icon: "square.grid.2x2", title: "仓库", active: tab == .repos) {
                    onSelectGallery(.repos)
                }
                Spacer()
                railButton(icon: "gearshape", title: "设置", active: tab == .settings) {
                    onSelectGallery(.settings)
                }
            case .workspace(let tab, let changeCount):
                railButton(icon: "folder", title: "浏览", active: tab == .browse) {
                    onSelectWorkspace(.browse)
                }
                ZStack(alignment: .topTrailing) {
                    railButton(icon: "pencil", title: "变更", active: tab == .changes) {
                        onSelectWorkspace(.changes)
                    }
                    if changeCount > 0 {
                        Text("\(changeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(AppTheme.modified)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -2)
                    }
                }
                railButton(icon: "clock", title: "历史", active: tab == .history) {
                    onSelectWorkspace(.history)
                }
                Spacer()
                railButton(icon: "gearshape", title: "设置", active: tab == .settings) {
                    onSelectWorkspace(.settings)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(width: 64)
        .background(AppTheme.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppTheme.line).frame(width: 1)
        }
    }

    private func railButton(icon: String, title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(active ? AppTheme.accent : AppTheme.inkTertiary)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(active ? AppTheme.accentSoft : .clear)
                )
                .overlay(alignment: .leading) {
                    if active {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.accent)
                            .frame(width: 3, height: 24)
                            .offset(x: -8)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
