import SwiftUI

struct CommitSheetView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let repo = store.selectedRepository {
                    Section {
                        Text("\(repo.name) · revision \(repo.revision + 1)")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.inkSecondary)
                    }
                }

                Section("待提交文件") {
                    ForEach(store.changes) { change in
                        Toggle(isOn: binding(for: change.id)) {
                            HStack(spacing: 10) {
                                if let status = change.node.status {
                                    StatusTag(status: status)
                                }
                                Text(change.node.name)
                                    .font(.body)
                            }
                        }
                    }
                }

                Section("提交说明") {
                    TextField("描述这次提交…", text: $store.commitMessage, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("提交变更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认提交") {
                        Task { await store.submitCommit() }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding(
            get: { store.selectedCommitPaths.contains(path) },
            set: { isSelected in
                if isSelected {
                    store.selectedCommitPaths.insert(path)
                } else {
                    store.selectedCommitPaths.remove(path)
                }
            }
        )
    }
}
