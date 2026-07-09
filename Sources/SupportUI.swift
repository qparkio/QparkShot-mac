import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
  let material: NSVisualEffectView.Material
  let blendingMode: NSVisualEffectView.BlendingMode

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = blendingMode
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    nsView.material = material
    nsView.blendingMode = blendingMode
  }
}

struct LocalizedPickerLabel: View {
  let language: AppLanguage

  @ObservedObject private var localization = LocalizationController.shared

  var body: some View {
    Text(language.displayName(in: localization.language))
      .environment(\.locale, localization.locale)
  }
}

func localized(_ key: String) -> String {
  LocalizationController.shared.text(key)
}

private func parseHexRGB(_ hexString: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
  let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
  guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
    return (1, 1, 1)
  }
  let r = CGFloat((value >> 16) & 0xFF) / 255.0
  let g = CGFloat((value >> 8) & 0xFF) / 255.0
  let b = CGFloat(value & 0xFF) / 255.0
  return (r, g, b)
}

extension NSColor {
  convenience init(hexString: String) {
    let rgb = parseHexRGB(hexString)
    self.init(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1.0)
  }
}

extension Color {
  init(hexString: String) {
    let rgb = parseHexRGB(hexString)
    self.init(.sRGB, red: Double(rgb.r), green: Double(rgb.g), blue: Double(rgb.b), opacity: 1.0)
  }
}

func hexString(from color: Color) -> String {
  let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
  let r = Int(round(ns.redComponent * 255))
  let g = Int(round(ns.greenComponent * 255))
  let b = Int(round(ns.blueComponent * 255))
  return String(format: "#%02X%02X%02X", r, g, b)
}
