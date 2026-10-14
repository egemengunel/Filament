import AppIntents

struct SetBulbPowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Bulb On or Off"

    @Parameter(title: "On")
    var on: Bool

    init() {}

    init(on: Bool) {
        self.on = on
    }

    func perform() async throws -> some IntentResult {
        try await BulbClient.send(.init(on: on))
        return .result()
    }
}

struct SetBulbBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Bulb Brightness"

    @Parameter(title: "Brightness", inclusiveRange: (1, 100))
    var level: Int

    init() {}

    init(level: Int) {
        self.level = level
    }

    func perform() async throws -> some IntentResult {
        try await BulbClient.send(.init(brightness: level))
        return .result()
    }
}

struct StepBulbBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Adjust Bulb Brightness"

    @Parameter(title: "Change")
    var delta: Int

    init() {}

    init(delta: Int) {
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        try await BulbClient.send(.init(delta: delta))
        return .result()
    }
}

struct ApplyBulbPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Bulb Preset"

    @Parameter(title: "Preset")
    var presetID: String

    init() {}

    init(presetID: String) {
        self.presetID = presetID
    }

    func perform() async throws -> some IntentResult {
        if let preset = BulbPreset.preset(id: presetID) {
            try await BulbClient.send(preset.command)
        }
        return .result()
    }
}
