import CoreGraphics

// macOS 15 and later give these Apple compositor surfaces full-display bounds
// even when their contents occupy only the Dock or notification banner area.
// System Settings panes also host tooltips in a separate extension process at
// the tooltip window level, which must not make the authorization sheet look
// obscured.
// The caller still verifies the foreground Settings/authorization app before
// and after every frame and input operation, including secure password focus.
func macMaintenanceCompositorSurface(bundle: String, appleSigned: Bool, layer: Int,
                                     bounds: CGRect, display: CGRect, systemMajor: Int) -> Bool {
    guard systemMajor >= 15, appleSigned else { return false }
    if bundle.hasPrefix("com.apple.") && bundle.hasSuffix("-Settings.extension") && layer == 101 {
        return true
    }
    guard !display.isEmpty,
          bounds == display else { return false }
    return bundle == "com.apple.dock" && layer == 20 ||
        bundle == "com.apple.notificationcenterui" && (layer == 21 || layer == 23)
}
