import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.949, green: 0.949, blue: 0.969)
    static let surface = Color.white
    static let surfaceSecondary = Color(red: 0.976, green: 0.976, blue: 0.984)
    static let ink = Color(red: 0.11, green: 0.11, blue: 0.118)
    static let inkSecondary = Color(red: 0.388, green: 0.388, blue: 0.400)
    static let inkTertiary = Color(red: 0.682, green: 0.682, blue: 0.698)
    static let accent = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let accentSoft = Color(red: 0.0, green: 0.478, blue: 1.0, opacity: 0.1)
    static let commit = Color(red: 0.204, green: 0.780, blue: 0.349)
    static let modified = Color(red: 1.0, green: 0.584, blue: 0.0)
    static let modifiedBackground = Color(red: 1.0, green: 0.973, blue: 0.922)
    static let addedBackground = Color(red: 0.929, green: 0.988, blue: 0.937)
    static let deleted = Color(red: 1.0, green: 0.231, blue: 0.188)
    static let deletedBackground = Color(red: 1.0, green: 0.941, blue: 0.937)
    static let line = Color.black.opacity(0.06)
    static let touch: CGFloat = 44
    static let radius: CGFloat = 14
    static let radiusSmall: CGFloat = 10
}

struct StatusTag: View {
    let status: SVNFileStatus

    var body: some View {
        Text("\(status.rawValue) \(status.label)")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var backgroundColor: Color {
        switch status {
        case .modified: return AppTheme.modifiedBackground
        case .added: return AppTheme.addedBackground
        case .deleted: return AppTheme.deletedBackground
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .modified: return Color(red: 0.788, green: 0.204, blue: 0.0)
        case .added: return Color(red: 0.141, green: 0.541, blue: 0.239)
        case .deleted: return Color(red: 0.843, green: 0.0, blue: 0.082)
        }
    }
}

struct SyncPill: View {
    let text: String
    var style: Style = .synced

    enum Style {
        case synced, changes, syncing
    }

    var body: some View {
        HStack(spacing: 5) {
            if style != .synced {
                Circle()
                    .fill(style == .changes ? AppTheme.modified : AppTheme.commit)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(AppTheme.commit)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(background)
        .foregroundStyle(foreground)
        .clipShape(Capsule())
    }

    private var background: Color {
        switch style {
        case .synced: return AppTheme.addedBackground
        case .changes: return AppTheme.modifiedBackground
        case .syncing: return AppTheme.surfaceSecondary
        }
    }

    private var foreground: Color {
        switch style {
        case .synced: return Color(red: 0.141, green: 0.541, blue: 0.239)
        case .changes: return Color(red: 0.788, green: 0.204, blue: 0.0)
        case .syncing: return AppTheme.inkSecondary
        }
    }
}

struct DiffLinesView: View {
    let lines: [DiffLine]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(lines) { line in
                HStack(spacing: 12) {
                    Text("\(line.lineNumber)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppTheme.inkTertiary)
                        .frame(width: 28, alignment: .trailing)
                    Text(line.text)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 12)
                .background(background(for: line.type))
                .foregroundStyle(foreground(for: line.type))
            }
        }
    }

    private func background(for type: DiffLine.LineType) -> Color {
        switch type {
        case .add: return AppTheme.addedBackground.opacity(0.65)
        case .delete: return AppTheme.deletedBackground.opacity(0.65)
        case .context: return .clear
        }
    }

    private func foreground(for type: DiffLine.LineType) -> Color {
        switch type {
        case .add: return Color(red: 0.141, green: 0.541, blue: 0.239)
        case .delete: return Color(red: 0.843, green: 0.0, blue: 0.082)
        case .context: return AppTheme.inkSecondary
        }
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(AppTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }
}
