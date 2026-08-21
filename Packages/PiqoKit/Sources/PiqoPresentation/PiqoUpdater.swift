import Foundation
import Sparkle

/// Sparkle 2 bridge. The appcast public key and HTTPS feed are supplied by the
/// signed release build; updates remain user initiated from the app menu.
@MainActor
public final class PiqoUpdater: NSObject {
    private var controller: SPUStandardUpdaterController?

    public override init() {
        super.init()
        guard let encodedKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !encodedKey.hasPrefix("$("),
              Data(base64Encoded: encodedKey)?.count == 32 else {
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    public func checkForUpdates() { controller?.checkForUpdates(nil) }
}
