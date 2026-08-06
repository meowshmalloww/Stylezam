import AppIntents

enum StylezamControlDestination: String, AppEnum {
    case capture
    case liveScreen

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Stylezam destination"
    )

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .capture: "Capture a Look",
        .liveScreen: "Live Screen",
    ]
}

/// Opens Stylezam with a typed destination. The scene handles navigation with
/// `onAppIntentExecution`; OpenIntent's system implementation performs the app
/// launch, so the widget extension never tries to open a custom URL scheme.
@available(iOS 26.0, *)
struct OpenStylezamIntent: OpenIntent, TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "Open Stylezam"
    static let description = IntentDescription(
        "Open Stylezam for a camera capture or an authorized Live Screen capture."
    )

    @Parameter(title: "Destination")
    var target: StylezamControlDestination

    /// Give iOS 26+ scene routing a stable value instead of asking the
    /// framework to synthesize one while the Control Center extension renders.
    var contentIdentifier: String {
        "stylezam.control.\(target.rawValue)"
    }

    init() {
        target = .capture
    }

    init(target: StylezamControlDestination) {
        self.target = target
    }
}
