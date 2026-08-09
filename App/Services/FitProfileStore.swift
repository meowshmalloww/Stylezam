import Foundation
import Observation

/// Stores the user's body measurements on this device only. Measurements are
/// never uploaded; the fit engine runs locally against extracted size charts.
@MainActor
@Observable
final class FitProfileStore {
    private let defaults: UserDefaults

    var measurements: BodyMeasurements {
        didSet { persistMeasurements() }
    }

    var displayUnit: MeasurementDisplayUnit {
        didSet { defaults.set(displayUnit.rawValue, forKey: Keys.displayUnit) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.measurements),
           let saved = try? JSONDecoder().decode(BodyMeasurements.self, from: data)
        {
            measurements = saved
        } else {
            measurements = .empty
        }
        displayUnit = defaults.string(forKey: Keys.displayUnit)
            .flatMap(MeasurementDisplayUnit.init(rawValue:))
            ?? (Locale.current.measurementSystem == .metric ? .centimeters : .inches)
    }

    func clear() {
        measurements = .empty
    }

    private func persistMeasurements() {
        guard let data = try? JSONEncoder().encode(measurements) else { return }
        defaults.set(data, forKey: Keys.measurements)
    }

    private enum Keys {
        static let measurements = "stylezam.fit.body-measurements"
        static let displayUnit = "stylezam.fit.display-unit"
    }
}
