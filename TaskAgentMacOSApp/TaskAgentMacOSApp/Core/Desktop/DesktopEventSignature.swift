import Foundation

enum DesktopEventSignature {
    // "TAGENT" in ASCII hex. Used to tag CGEvents we synthesize so they can be ignored by user-interruption monitors.
    static let syntheticEventUserData: Int64 = 0x544147454E54
}

