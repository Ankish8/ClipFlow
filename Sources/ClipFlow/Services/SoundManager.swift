import AppKit

/// Centralized sound playback for ClipFlow events.
/// Reads user preferences from UserDefaults for sound selection and per-event toggles.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    // All macOS system sounds available in /System/Library/Sounds/
    static let availableSounds: [String] = [
        "Tink", "Pop", "Purr", "Glass", "Ping",
        "Blow", "Bottle", "Frog", "Funk", "Hero",
        "Morse", "Sosumi", "Submarine", "Basso"
    ]

    /// Sound events that can be individually toggled
    enum Event: String, CaseIterable {
        case clipboardCapture = "sound.clipboardCapture"
        case paste            = "sound.paste"
        case overlayOpen      = "sound.overlayOpen"
        case overlayClose     = "sound.overlayClose"

        var label: String {
            switch self {
            case .clipboardCapture: return "Clipboard capture"
            case .paste:            return "Paste"
            case .overlayOpen:      return "Overlay open"
            case .overlayClose:     return "Overlay close"
            }
        }

        /// Default on/off state for each event
        var defaultEnabled: Bool {
            switch self {
            case .clipboardCapture: return true
            case .paste:            return true
            case .overlayOpen:      return false
            case .overlayClose:     return false
            }
        }
    }

    private init() {}

    /// Play the selected sound for a given event (if master toggle + event toggle are on).
    func play(_ event: Event) {
        guard UserDefaults.standard.bool(forKey: "enableSounds") else { return }
        guard isEnabled(event) else { return }
        let name = selectedSound
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// Preview a sound by name (ignores toggles — used in settings picker).
    func preview(_ soundName: String) {
        NSSound(named: NSSound.Name(soundName))?.play()
    }

    var selectedSound: String {
        get { UserDefaults.standard.string(forKey: "selectedSound") ?? "Tink" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedSound") }
    }

    func isEnabled(_ event: Event) -> Bool {
        let key = event.rawValue
        if UserDefaults.standard.object(forKey: key) == nil {
            return event.defaultEnabled
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    func setEnabled(_ enabled: Bool, for event: Event) {
        UserDefaults.standard.set(enabled, forKey: event.rawValue)
    }
}
