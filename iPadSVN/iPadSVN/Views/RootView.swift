import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if store.isInWorkspace {
                WorkspaceShellView()
            } else {
                GalleryShellView()
            }

            if let message = store.toastMessage {
                VStack {
                    Spacer()
                    ToastView(message: message)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                                withAnimation {
                                    if store.toastMessage == message {
                                        store.toastMessage = nil
                                    }
                                }
                            }
                        }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: store.toastMessage)
            }
        }
        .task { await store.bootstrap() }
        .sheet(isPresented: $store.showCommitSheet) {
            CommitSheetView()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.showRepoSwitcher) {
            RepoSwitcherSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.showCheckoutSheet) {
            CheckoutSheetView()
                .environmentObject(store)
        }
    }
}

private struct GalleryShellView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            TopBarView(
                title: "我的仓库",
                subtitle: "\(store.repositories.count) 个工作副本",
                showsBack: false,
                syncText: nil,
                revisionText: nil,
                isSyncing: false,
                onBack: {},
                onTitleTap: {}
            )

            HStack(spacing: 0) {
                RailView(
                    mode: .gallery(store.galleryTab),
                    onSelectGallery: { store.galleryTab = $0 },
                    onSelectWorkspace: { _ in }
                )

                VStack(spacing: 0) {
                    HeroHeaderView(
                        title: store.galleryTab == .repos ? "\(store.repositories.count)" : nil,
                        titleSuffix: store.galleryTab == .repos ? " 个仓库" : "设置",
                        subtitle: store.galleryTab == .repos ? "轻点进入，浏览文件、提交变更" : "账号与全局选项"
                    )

                    switch store.galleryTab {
                    case .repos:
                        RepoGalleryView()
                    case .settings:
                        GlobalSettingsView()
                    }
                }
            }
        }
    }
}

struct WorkspaceShellView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                TopBarView(
                    title: store.selectedRepository?.name ?? "",
                    subtitle: store.selectedRepository?.url ?? "",
                    showsBack: true,
                    syncText: syncText,
                    revisionText: store.selectedRepository.map { "r\($0.revision)" },
                    isSyncing: store.isSyncing,
                    onBack: { store.leaveWorkspace() },
                    onTitleTap: { store.showRepoSwitcher = true }
                )

                HStack(spacing: 0) {
                    RailView(
                        mode: .workspace(store.workspaceTab, changeCount: store.changes.count),
                        onSelectGallery: { _ in },
                        onSelectWorkspace: { tab in
                            if tab != .browse {
                                store.selectedFilePath = nil
                            }
                            store.workspaceTab = tab
                        }
                    )

                    VStack(spacing: 0) {
                        workspaceHero
                        workspaceContent
                    }
                }
            }

            if shouldShowFloatBar {
                FloatActionBar(
                    changeCount: store.changes.count,
                    onUpdate: { Task { await store.updateRepository() } },
                    onCommit: { store.openCommitSheet() }
                )
                .padding(.bottom, 16)
                .padding(.leading, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: shouldShowFloatBar)
    }

    private var shouldShowFloatBar: Bool {
        !store.changes.isEmpty && (store.workspaceTab == .changes || store.workspaceTab == .browse)
    }

    private var syncText: String? {
        if store.isSyncing { return "同步中…" }
        if store.changes.isEmpty { return "已同步" }
        return "\(store.changes.count) 处变更"
    }

    @ViewBuilder
    private var workspaceHero: some View {
        switch store.workspaceTab {
        case .browse:
            EmptyView()
        case .changes:
            HeroHeaderView(
                title: "\(store.changes.count)",
                titleSuffix: " 处待提交",
                subtitle: "当前仓库 · 轻点展开 Diff"
            )
        case .history:
            HeroHeaderView(
                title: "提交历史",
                titleSuffix: nil,
                subtitle: store.selectedRepository.map { "\($0.name) · r\($0.revision)" } ?? ""
            )
        case .settings:
            HeroHeaderView(
                title: "仓库设置",
                titleSuffix: nil,
                subtitle: store.selectedRepository?.name ?? ""
            )
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch store.workspaceTab {
        case .browse:
            BrowseView()
        case .changes:
            ChangesView()
        case .history:
            HistoryView()
        case .settings:
            RepositorySettingsView()
        }
    }
}

struct TopBarView: View {
    let title: String
    let subtitle: String
    let showsBack: Bool
    let syncText: String?
    let revisionText: String?
    let isSyncing: Bool
    let onBack: () -> Void
    let onTitleTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: AppTheme.touch, height: AppTheme.touch)
            }
            .buttonStyle(.plain)
            .opacity(showsBack ? 1 : 0)
            .disabled(!showsBack)

            Button(action: onTitleTap) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        if showsBack {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.inkTertiary)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.inkTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let syncText {
                SyncPill(
                    text: syncText,
                    style: isSyncing ? .syncing : (syncText.contains("变更") ? .changes : .synced)
                )
            }

            if let revisionText {
                Text(revisionText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(AppTheme.surfaceSecondary)
                    .foregroundStyle(AppTheme.inkSecondary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: AppTheme.touch)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.line).frame(height: 1) }
    }
}

struct HeroHeaderView: View {
    let title: String?
    let titleSuffix: String?
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title, let titleSuffix {
                HStack(spacing: 0) {
                    Text(title)
                        .foregroundStyle(AppTheme.accent)
                    Text(titleSuffix)
                }
                .font(.system(size: 26, weight: .bold))
            } else if let titleSuffix {
                Text(titleSuffix)
                    .font(.system(size: 26, weight: .bold))
            }

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(AppTheme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.line).frame(height: 1) }
    }
}
