import CoreGraphics

/// Breakpoints for window reflow. Fixed 280+300 side columns were clipping instead of adapting.
enum ListrAdaptiveLayout {
    static let findingsRailMinWidth: CGFloat = 720
    static let wideSidebarMinWidth: CGFloat = 900
    static let wideSidebarWidth: CGFloat = 280
    static let compactSidebarWidth: CGFloat = 220
    static let findingsRailWidth: CGFloat = 300

    static func sidebarWidth(forAvailableWidth width: CGFloat) -> CGFloat {
        width >= wideSidebarMinWidth ? wideSidebarWidth : compactSidebarWidth
    }

    static func showsFindingsRail(forAvailableWidth width: CGFloat) -> Bool {
        width >= findingsRailMinWidth
    }
}
