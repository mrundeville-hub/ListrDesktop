import Testing
@testable import ListrDesktop

@Suite("Adaptive layout")
struct ListrAdaptiveLayoutTests {
    @Test("hides findings rail below breakpoint so the reader can reflow")
    func findingsRailBreakpoint() {
        #expect(!ListrAdaptiveLayout.showsFindingsRail(forAvailableWidth: 719))
        #expect(ListrAdaptiveLayout.showsFindingsRail(forAvailableWidth: 720))
    }

    @Test("narrows sidebar under the wide breakpoint")
    func sidebarWidthBreakpoint() {
        #expect(ListrAdaptiveLayout.sidebarWidth(forAvailableWidth: 899) == ListrAdaptiveLayout.compactSidebarWidth)
        #expect(ListrAdaptiveLayout.sidebarWidth(forAvailableWidth: 900) == ListrAdaptiveLayout.wideSidebarWidth)
    }
}
