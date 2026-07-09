import AppKit
import SwiftUI

enum QPARKDesign {
  static let compactSpacing: CGFloat = 6
  static let standardSpacing: CGFloat = 10
  static let sectionSpacing: CGFloat = 16
  static let pagePadding: CGFloat = 18
  static let cardRadius: CGFloat = 12
  static let previewRadius: CGFloat = 10

  static let brandCyan = Color(red: 0.30, green: 0.78, blue: 0.84)
  static let brandViolet = Color(red: 0.62, green: 0.48, blue: 0.88)
  static let canvas = Color(nsColor: .windowBackgroundColor).opacity(0.24)
}

struct QPARKSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var emphasized = false

  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: QPARKDesign.cardRadius, style: .continuous)
          .fill(
            reduceTransparency
              ? Color(nsColor: .controlBackgroundColor)
              : Color.primary.opacity(emphasized ? 0.075 : 0.045)
          )
      }
      .overlay {
        RoundedRectangle(cornerRadius: QPARKDesign.cardRadius, style: .continuous)
          .stroke(Color.primary.opacity(0.10), lineWidth: 1)
      }
  }
}

extension View {
  func qparkSurface(emphasized: Bool = false) -> some View {
    modifier(QPARKSurface(emphasized: emphasized))
  }
}

struct WorkspaceStatusBanner: View {
  let status: WorkspaceStatus

  private var tint: Color {
    switch status.kind {
    case .info: return QPARKDesign.brandCyan
    case .success: return .green
    case .warning: return .orange
    case .error: return .red
    }
  }

  var body: some View {
    Label(status.message, systemImage: status.kind.systemImage)
      .font(.callout)
      .foregroundStyle(.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .background(.regularMaterial, in: Capsule())
      .overlay {
        Capsule().stroke(tint.opacity(0.45), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
      .accessibilityElement(children: .combine)
  }
}

struct BrandMark: View {
  var size: CGFloat = 28

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        .fill(
          LinearGradient(
            colors: [QPARKDesign.brandCyan.opacity(0.92), QPARKDesign.brandViolet.opacity(0.92)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      Image(systemName: "camera.aperture")
        .font(.system(size: size * 0.58, weight: .semibold))
        .foregroundStyle(.white)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
