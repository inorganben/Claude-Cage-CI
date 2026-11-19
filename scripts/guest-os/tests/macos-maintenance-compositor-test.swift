import CoreGraphics

@main
struct MaintenanceCompositorTests {
    static func main() {
        let display = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        func accepted(_ bundle: String, _ layer: Int, _ bounds: CGRect,
                      signed: Bool = true, major: Int = 15) -> Bool {
            macMaintenanceCompositorSurface(bundle: bundle, appleSigned: signed,
                                            layer: layer, bounds: bounds, display: display, systemMajor: major)
        }
        precondition(accepted("com.apple.dock", 20, display))
        precondition(accepted("com.apple.notificationcenterui", 21, display))
        precondition(accepted("com.apple.notificationcenterui", 23, display))
        precondition(accepted("com.apple.Sharing-Settings.extension", 101,
                              CGRect(x: 1003, y: 536, width: 150, height: 58), major: 26))
        precondition(!accepted("com.apple.dock", 20, display, signed: false))
        precondition(!accepted("com.apple.notificationcenterui", 21, display, signed: false))
        precondition(!accepted("com.apple.notificationcenterui", 23, display, signed: false))
        precondition(!accepted("com.apple.Sharing-Settings.extension", 101, display, signed: false, major: 26))
        precondition(!accepted("com.example.Sharing-Settings.extension", 101, display, major: 26))
        precondition(!accepted("com.apple.Sharing-Settings.extension", 0, display, major: 26))
        precondition(!accepted("com.example.notificationcenterui", 23, display))
        precondition(!accepted("com.apple.dock", 0, display))
        precondition(!accepted("com.apple.notificationcenterui", 20, display))
        precondition(!accepted("com.apple.notificationcenterui", 0, display))
        precondition(!accepted("com.apple.dock", 20, CGRect(x: 0, y: 700, width: 1600, height: 300)))
        precondition(!accepted("com.apple.notificationcenterui", 21, display.offsetBy(dx: 1, dy: 0)))
        precondition(!accepted("com.apple.notificationcenterui", 23, display.offsetBy(dx: 1, dy: 0)))
        precondition(accepted("com.apple.dock", 20, display, major: 26))
        precondition(accepted("com.apple.notificationcenterui", 21, display, major: 26))
        precondition(accepted("com.apple.notificationcenterui", 23, display, major: 26))
        precondition(!accepted("com.apple.dock", 20, display, major: 14))
        print("macOS maintenance compositor checks passed")
    }
}
