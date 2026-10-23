import HyCodeWorkspace
import SwiftUI

/// The switcher and welcome page share one project identity and click target.
struct WorkbenchProjectRow: View {
    let project: RecentProject
    var active = false
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                WorkbenchProjectBadge(project: project, size: 20).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name).font(.system(size: 13, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                    Text(project.path).font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if active {
                    Image(systemName: "checkmark").font(.system(size: 10)).foregroundStyle(WorkbenchColors.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: WorkbenchMetrics.projectPopupRowHeight)
            .padding(.horizontal, 12)
        }
        .buttonStyle(WorkbenchButtonStyle(active: active || highlighted, neutral: !highlighted))
        .help(project.path).accessibilityLabel("\(project.name)，\(project.path)")
    }
}

struct WorkbenchProjectBadge: View {
    let project: RecentProject?
    let size: CGFloat
    private let colors: [Color] = [
        Color(red: 0.58, green: 0.34, blue: 0.82), Color(red: 0.29, green: 0.52, blue: 0.79),
        Color(red: 0.24, green: 0.62, blue: 0.55), Color(red: 0.77, green: 0.45, blue: 0.31),
        Color(red: 0.54, green: 0.64, blue: 0.32), Color(red: 0.40, green: 0.35, blue: 0.76),
    ]
    var body: some View {
        if let project {
            Text(project.initials).font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(.white).frame(width: size, height: size)
                .background(colors[project.colorIndex], in: RoundedRectangle(cornerRadius: 4))
        } else {
            HyCodeBrandIcon(size: size)
        }
    }
}
