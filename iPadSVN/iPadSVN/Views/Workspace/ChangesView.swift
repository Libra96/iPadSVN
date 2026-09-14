import SwiftUI

struct ChangesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var diffCache: [String: [DiffLine]] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if store.changes.isEmpty {
                    ContentUnavailableView("没有待提交的变更", systemImage: "checkmark.circle")
                        .padding(.top, 48)
                } else {
                    ForEach(Array(store.changes.enumerated()), id: \.element.id) { index, change in
                        ChangeEventView(
                            change: change,
                            isExpanded: store.expandedChangePath == change.id,
                            isLast: index == store.changes.count - 1,
                            diffLines: store.expandedChangePath == change.id ? diffCache[change.id] : nil
                        ) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                let opening = store.expandedChangePath != change.id
                                store.expandedChangePath = opening ? change.id : nil
                                if opening {
                                    Task {
                                        let lines = await store.loadDiff(for: change.id)
                                        diffCache[change.id] = lines
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
    }
}

private struct ChangeEventView: View {
    let change: SVNChange
    let isExpanded: Bool
    let isLast: Bool
    let diffLines: [DiffLine]?
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(isExpanded ? AppTheme.accent : AppTheme.surface)
                    .overlay(
                        Circle()
                            .stroke(isExpanded ? AppTheme.accent : AppTheme.line, lineWidth: 2.5)
                    )
                    .frame(width: 12, height: 12)
                    .shadow(color: isExpanded ? AppTheme.accentSoft : .clear, radius: 4)

                if !isLast {
                    Rectangle()
                        .fill(AppTheme.line)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 4)
                }
            }
            .frame(width: 28)
            .padding(.top, 18)

            VStack(spacing: 0) {
                Button(action: onTap) {
                    HStack(spacing: 12) {
                        FileIconView(ext: change.node.ext, isFolder: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.node.name)
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppTheme.ink)
                            Text(directoryPath)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.inkTertiary)
                        }
                        Spacer()
                        if let status = change.node.status {
                            StatusTag(status: status)
                        }
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)

                if isExpanded, let lines = diffLines, !lines.isEmpty {
                    DiffLinesView(lines: lines)
                        .background(AppTheme.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous)
                                .stroke(AppTheme.line, lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous)
                    .stroke(isExpanded ? AppTheme.accent.opacity(0.25) : AppTheme.line, lineWidth: 1)
            )
            .shadow(color: isExpanded ? AppTheme.accent.opacity(0.08) : .black.opacity(0.04), radius: isExpanded ? 12 : 4, y: 2)
        }
    }

    private var directoryPath: String {
        let parts = change.node.path.split(separator: "/").dropLast()
        if parts.isEmpty { return "/" }
        return parts.joined(separator: "/") + "/"
    }
}
