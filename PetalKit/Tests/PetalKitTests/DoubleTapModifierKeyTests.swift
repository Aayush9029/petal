import Testing
@testable import Shared

@Test
func doubleTapModifierKeyHasAllExpectedCases() {
    #expect(DoubleTapModifierKey.allCases.count == 5)
    #expect(DoubleTapModifierKey.allCases.contains(.fn))
    #expect(DoubleTapModifierKey.allCases.contains(.command))
    #expect(DoubleTapModifierKey.allCases.contains(.option))
    #expect(DoubleTapModifierKey.allCases.contains(.control))
    #expect(DoubleTapModifierKey.allCases.contains(.shift))
}

@Test
func doubleTapModifierKeyRawValuesAreStable() {
    #expect(DoubleTapModifierKey.fn.rawValue == "fn")
    #expect(DoubleTapModifierKey.command.rawValue == "command")
    #expect(DoubleTapModifierKey.option.rawValue == "option")
    #expect(DoubleTapModifierKey.control.rawValue == "control")
    #expect(DoubleTapModifierKey.shift.rawValue == "shift")
}

@Test
func doubleTapModifierKeyDisplayNameIsNotEmpty() {
    for key in DoubleTapModifierKey.allCases {
        #expect(!key.displayName.isEmpty)
    }
}

@Test
func doubleTapModifierKeyDefaultIsFn() {
    let defaultKey: DoubleTapModifierKey = .fn
    #expect(defaultKey == .fn)
}

@Test
func doubleTapModifierKeyRoundTripsCodable() throws {
    for key in DoubleTapModifierKey.allCases {
        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(DoubleTapModifierKey.self, from: data)
        #expect(decoded == key)
    }
}
