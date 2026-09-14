import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(store.history.enumerated()), id: \.element.id) { index, record in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(AppTheme.accent)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(AppTheme.accentSoft, lineWidth: 2))
                            if index < store.history.count - 1 {
                                Rectangle()
                                    .fill(AppTheme.line)
                                    .frame(width: 2)
                                    .frame(minHeight: 36)
                                    .padding(.top, 4)
                            }
                        }
                        .frame(width: 28)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("r\(record.revision)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppTheme.accent)
                            Text(record.message)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.ink)
                            Text("\(record.author) · \(record.dateDescription)")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.inkTertiary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous)
                                .stroke(AppTheme.line, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }
}
