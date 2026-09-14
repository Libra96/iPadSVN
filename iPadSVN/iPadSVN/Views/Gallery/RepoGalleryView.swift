import SwiftUI

struct RepoGalleryView: View {
    @EnvironmentObject private var store: AppStore

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.repositories) { repo in
                    RepoCardView(repo: repo) {
                        Task { await store.enterRepository(repo) }
                    }
                }

                Button {
                    store.showCheckoutSheet = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppTheme.accentSoft, lineWidth: 2)
                            )
                        Text("Checkout 新仓库")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .background(AppTheme.surface.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                            .foregroundStyle(AppTheme.line)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
    }

}

private struct RepoCardView: View {
    let repo: SVNRepository
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(repo.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)

                    Text(repo.url)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.inkTertiary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        chip("r\(repo.revision)")
                        chip("libsvn")
                    }

                    Text("上次同步 · \(repo.lastSyncDescription)")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.inkTertiary)
                }
                .padding(18)
            }
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func chip(_ text: String, highlighted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(highlighted ? AppTheme.modifiedBackground : AppTheme.surfaceSecondary)
            .foregroundStyle(highlighted ? Color(red: 0.788, green: 0.204, blue: 0.0) : AppTheme.inkSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
