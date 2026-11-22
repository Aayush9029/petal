import Carbon.HIToolbox

public struct DoubleTapKey: Codable, Hashable, Sendable {
    public let keyCode: Int
    public let isModifier: Bool

    public init(keyCode: Int, isModifier: Bool) {
        self.keyCode = keyCode
        self.isModifier = isModifier
    }

    public static let unconfigured = DoubleTapKey(keyCode: -1, isModifier: false)

    public var isConfigured: Bool { keyCode >= 0 }

    public var displayName: String {
        guard isConfigured else { return "" }
        if isModifier {
            return Self.modifierName(for: keyCode)
        }
        return Self.regularKeyName(for: keyCode)
    }

    private static func modifierName(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_Command, kVK_RightCommand:   return "\u{2318}"
        case kVK_Shift, kVK_RightShift:       return "\u{21E7}"
        case kVK_Option, kVK_RightOption:      return "\u{2325}"
        case kVK_Control, kVK_RightControl:    return "\u{2303}"
        case kVK_Function:                     return "fn"
        default:                               return "Mod \(keyCode)"
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func regularKeyName(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_Space:         return "\u{2423}"
        case kVK_Return:        return "\u{21A9}"
        case kVK_Escape:        return "\u{238B}"
        case kVK_Delete:        return "\u{232B}"
        case kVK_ForwardDelete: return "\u{2326}"
        case kVK_UpArrow:       return "\u{2191}"
        case kVK_DownArrow:     return "\u{2193}"
        case kVK_LeftArrow:     return "\u{2190}"
        case kVK_RightArrow:    return "\u{2192}"
        case kVK_CapsLock:      return "\u{21EA}"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:      return "Key \(keyCode)"
        }
    }
}
