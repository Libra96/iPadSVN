import SwiftUI

struct GlobalSettingsView: View {
    var body: some View {
        Form {
            Section("账号") {
                LabeledContent("SVN 服务器", value: "svn.company.com")
                LabeledContent("用户名", value: "developer")
                LabeledContent("默认分支", value: "trunk")
            }
            Section("操作") {
                LabeledContent("Checkout 新仓库", value: "›")
                LabeledContent("清除全部缓存", value: "›")
            }
            Section {
                Text("内嵌 libsvn，Checkout 后直连 SVN 服务器。账号密码保存在本机 Keychain。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.inkSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
    }
}

struct RepositorySettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            if let repo = store.selectedRepository {
                Section("仓库信息") {
                    LabeledContent("SVN 地址", value: repo.url)
                    LabeledContent("当前版本", value: "r\(repo.revision)")
                    LabeledContent("本地路径", value: repo.localPath)
                }
                Section("操作") {
                    Button("更新到最新") {
                        Task { await store.updateRepository() }
                    }
                    Button("还原全部变更", role: .destructive) {}
                    Button("移除工作副本", role: .destructive) {}
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
    }
}

struct CheckoutSheetView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = "https://svn.example.com/repo/trunk"
    @State private var name = "my-project"
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("仓库地址") {
                    TextField("SVN URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("本地名称") {
                    TextField("工作副本名称", text: $name)
                }
                Section("SVN 账号") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                }
            }
            .navigationTitle("Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") {
                        Task {
                            await store.checkoutRepository(
                                url: url,
                                name: name,
                                username: username,
                                password: password
                            )
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct RepoSwitcherSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.repositories) { repo in
                Button {
                    Task { await store.switchRepository(repo) }
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "book.closed")
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repo.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(repo.id == store.selectedRepositoryID ? AppTheme.accent : AppTheme.ink)
                            Text("\(repo.url) · r\(repo.revision)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(AppTheme.inkTertiary)
                        }
                        Spacer()
                        if repo.id == store.selectedRepositoryID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }
            }
            .navigationTitle("切换仓库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
