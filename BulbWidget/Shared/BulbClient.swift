import Foundation

/// Bulb state as reported by the local HomeKit bridge (tapo_home/bridge.py).
struct BulbState: Codable, Sendable {
    var room: String
    var name: String
    var reachable: Bool
    var on: Bool
    var brightness: Int
    var hue: Int
    var saturation: Int
    /// Kelvin while in white mode, 0 while showing a color.
    var colorTemp: Int

    enum CodingKeys: String, CodingKey {
        case room, name, reachable, on, brightness, hue, saturation
        case colorTemp = "color_temp"
    }

    static let preview = BulbState(
        room: "Bedroom", name: "Bulb", reachable: true, on: true,
        brightness: 20, hue: 0, saturation: 0, colorTemp: 2500
    )
    static let noResponse = BulbState(
        room: "Bedroom", name: "Bulb", reachable: false, on: false,
        brightness: 0, hue: 0, saturation: 0, colorTemp: 0
    )

    var isLit: Bool { reachable && on }
}

/// Talks to the bridge's local API, which only listens on 127.0.0.1.
enum BulbClient {
    struct Command: Encodable {
        var on: Bool?
        var brightness: Int?
        var delta: Int?
        var hue: Int?
        var saturation: Int?
        var colorTemp: Int?

        enum CodingKeys: String, CodingKey {
            case on, brightness, delta, hue, saturation
            case colorTemp = "color_temp"
        }
    }

    private static let baseURL = URL(string: "http://127.0.0.1:51828")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        return URLSession(configuration: configuration)
    }()

    static func state() async -> BulbState {
        do {
            let (data, _) = try await session.data(from: baseURL.appending(path: "state"))
            return try JSONDecoder().decode(BulbState.self, from: data)
        } catch {
            return .noResponse
        }
    }

    static func send(_ command: Command) async throws {
        var request = URLRequest(url: baseURL.appending(path: "set"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(command)
        _ = try await session.data(for: request)
    }
}
