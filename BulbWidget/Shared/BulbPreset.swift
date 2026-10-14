import SwiftUI

/// The user's favourite Tapo presets: a color (or white temperature) plus a brightness.
struct BulbPreset: Identifiable, Sendable {
    enum Light: Sendable {
        case color(hue: Int, saturation: Int)
        case white(kelvin: Int)
    }

    let id: String
    let name: LocalizedStringResource
    let light: Light
    let brightness: Int
    /// Swatch shown in the widget, matching the Tapo app.
    let swatch: Color

    static let all: [BulbPreset] = [
        BulbPreset(id: "red", name: "Red", light: .color(hue: 358, saturation: 99), brightness: 18,
                   swatch: Color(red: 1, green: 0.01, blue: 0.04)),
        BulbPreset(id: "orange", name: "Orange", light: .color(hue: 28, saturation: 100), brightness: 20,
                   swatch: Color(red: 1, green: 0.47, blue: 0)),
        BulbPreset(id: "warm", name: "Warm White", light: .white(kelvin: 2500), brightness: 20,
                   swatch: Color(red: 0.98, green: 0.82, blue: 0.6)),
        BulbPreset(id: "cool", name: "Cool White", light: .white(kelvin: 4500), brightness: 100,
                   swatch: Color(red: 0.99, green: 0.94, blue: 0.89)),
    ]

    static func preset(id: String) -> BulbPreset? {
        all.first { $0.id == id }
    }

    var command: BulbClient.Command {
        switch light {
        case let .color(hue, saturation):
            BulbClient.Command(brightness: brightness, hue: hue, saturation: saturation)
        case let .white(kelvin):
            BulbClient.Command(brightness: brightness, colorTemp: kelvin)
        }
    }

    /// Whether the bulb is currently showing this preset's color (brightness may differ).
    func matches(_ state: BulbState) -> Bool {
        guard state.isLit else { return false }
        switch light {
        case let .color(hue, saturation):
            let hueDistance = abs(state.hue - hue) % 360
            return state.colorTemp == 0
                && min(hueDistance, 360 - hueDistance) <= 4
                && abs(state.saturation - saturation) <= 5
        case let .white(kelvin):
            return abs(state.colorTemp - kelvin) <= 100
        }
    }
}

extension BulbState {
    /// Tint for the tile icon and slider, following the bulb's color like the Home app.
    var lightTint: Color {
        colorTemp == 0
            ? Color(hue: Double(hue) / 360, saturation: Double(saturation) / 100, brightness: 1)
            : .orange
    }
}
