import Foundation
import Observation

@Observable
final class OverlayStore {
    var isPresented: Bool {
        didSet { defaults.set(isPresented, forKey: Keys.isPresented) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPresented = defaults.object(forKey: Keys.isPresented) as? Bool ?? false
    }

    func toggle() {
        isPresented.toggle()
    }
}

private enum Keys {
    static let isPresented = "overlay.isPresented"
}
