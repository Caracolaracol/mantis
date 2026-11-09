import SwiftUI

enum CapturePlatform {
    static var supportsNativeMicrophone: Bool {
        #if MANTIS_SONOMA
        // Exercise the Sonoma path even when this edition is tested on a newer Mac.
        false
        #else
        if #available(macOS 15, *) { true } else { false }
        #endif
    }

    static var usesLegacyWindowPolicy: Bool {
        #if MANTIS_SONOMA
        true
        #else
        if #available(macOS 15, *) { false } else { true }
        #endif
    }
}

extension Scene {
    func mantisLaunchBehavior(startWithoutWindow: Bool) -> some Scene {
        #if MANTIS_SONOMA
        self
        #else
        self.defaultLaunchBehavior(startWithoutWindow ? .suppressed : .presented)
            .restorationBehavior(.disabled)
        #endif
    }

    func mantisRestorationBehavior() -> some Scene {
        #if MANTIS_SONOMA
        self
        #else
        self.restorationBehavior(.disabled)
        #endif
    }
}
