import AppKit
import SwiftUI

struct ShortcutRecorder: View {
  @Binding var shortcut: HotkeySettings
  let otherShortcut: HotkeySettings
  let identifier: String
  @State private var errorKey: String?

  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      ShortcutRecorderButton(
        shortcut: shortcut,
        identifier: identifier,
        onRecord: record
      )
      .frame(width: 190, height: 28)
      .accessibilityLabel(localized("settings.record_shortcut"))
      .accessibilityValue(hotkeyDisplayString(shortcut))

      if let errorKey {
        Text(localized(errorKey))
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: 260, alignment: .trailing)
      }
    }
  }

  private func record(_ next: HotkeySettings) {
    if let error = next.validationError(comparedWith: otherShortcut) {
      errorKey = error == .duplicate
        ? "settings.shortcut_duplicate"
        : "settings.shortcut_invalid"
      return
    }
    errorKey = nil
    shortcut = HotkeySettings(
      enabled: shortcut.enabled,
      key: next.normalizedKey,
      modifiers: next.normalizedModifiers
    )
  }
}

private struct ShortcutRecorderButton: NSViewRepresentable {
  let shortcut: HotkeySettings
  let identifier: String
  let onRecord: (HotkeySettings) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(title: hotkeyDisplayString(shortcut), target: context.coordinator, action: #selector(Coordinator.startRecording))
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.setAccessibilityLabel(localized("settings.record_shortcut"))
    button.setAccessibilityIdentifier(identifier)
    context.coordinator.button = button
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.parent = self
    if !context.coordinator.isRecording {
      button.title = hotkeyDisplayString(shortcut)
    }
  }

  static func dismantleNSView(_ nsView: NSButton, coordinator: Coordinator) {
    coordinator.stopRecording()
  }

  final class Coordinator: NSObject {
    var parent: ShortcutRecorderButton
    weak var button: NSButton?
    var monitor: Any?
    var isRecording = false

    init(parent: ShortcutRecorderButton) {
      self.parent = parent
    }

    deinit {
      stopRecording()
    }

    @objc func startRecording() {
      guard !isRecording else {
        stopRecording()
        return
      }
      isRecording = true
      button?.title = localized("settings.shortcut_recording")
      button?.setAccessibilityValue(localized("settings.shortcut_recording"))
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        self?.handle(event) ?? event
      }
    }

    func stopRecording() {
      if let monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
      isRecording = false
      button?.title = hotkeyDisplayString(parent.shortcut)
      button?.setAccessibilityValue(hotkeyDisplayString(parent.shortcut))
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
      if event.keyCode == 53 {
        stopRecording()
        return nil
      }

      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      var names: [String] = []
      if modifiers.contains(.control) { names.append("control") }
      if modifiers.contains(.option) { names.append("option") }
      if modifiers.contains(.shift) { names.append("shift") }
      if modifiers.contains(.command) { names.append("command") }
      let key = (event.charactersIgnoringModifiers ?? "").uppercased()
      let value = HotkeySettings(enabled: true, key: key, modifiers: names)
      parent.onRecord(value)
      stopRecording()
      return nil
    }
  }
}

func hotkeyDisplayString(_ shortcut: HotkeySettings) -> String {
  guard shortcut.enabled else { return "—" }
  let symbols = shortcut.normalizedModifiers.compactMap { value -> String? in
    switch value {
    case "control": return "⌃"
    case "option": return "⌥"
    case "shift": return "⇧"
    case "command": return "⌘"
    default: return nil
    }
  }
  return symbols.joined() + shortcut.normalizedKey
}
