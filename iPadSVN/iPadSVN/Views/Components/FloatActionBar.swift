import SwiftUI

struct FloatActionBar: View {
    let changeCount: Int
    let onUpdate: () -> Void
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("\(changeCount) 处变更")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.inkSecondary)
                .padding(.horizontal, 12)

            divider

            Button("更新", action: onUpdate)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.inkSecondary)
                .frame(minHeight: AppTheme.touch)

            divider

            Button("提交", action: onCommit)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .frame(minHeight: AppTheme.touch)
                .background(AppTheme.commit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.line)
            .frame(width: 1, height: 24)
    }
}
