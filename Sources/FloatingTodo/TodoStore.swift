import Combine
import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var deadline: Date
    var isCompleted: Bool
}

struct TodoColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    private enum CodingKeys: String, CodingKey {
        case red, green, blue
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    init(from decoder: Decoder) throws {
        let components = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            red: components.decode(Double.self, forKey: .red),
            green: components.decode(Double.self, forKey: .green),
            blue: components.decode(Double.self, forKey: .blue)
        )
    }

    fileprivate static func clamp(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct TodoHSB: Codable, Equatable {
    let hue: Double
    let saturation: Double
    let brightness: Double

    private enum CodingKeys: String, CodingKey {
        case hue, saturation, brightness
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = TodoColor.clamp(hue)
        self.saturation = TodoColor.clamp(saturation)
        self.brightness = TodoColor.clamp(brightness)
    }

    init(from decoder: Decoder) throws {
        let components = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hue: components.decode(Double.self, forKey: .hue),
            saturation: components.decode(Double.self, forKey: .saturation),
            brightness: components.decode(Double.self, forKey: .brightness)
        )
    }

    init(color: TodoColor, fallbackHue: Double = 0, fallbackSaturation: Double = 0) {
        let brightest = max(color.red, color.green, color.blue)
        let darkest = min(color.red, color.green, color.blue)
        let chroma = brightest - darkest

        guard chroma > 0 else {
            // An RGB gray has no hue. Black has no recoverable saturation either.
            self.init(
                hue: fallbackHue,
                saturation: brightest == 0 ? fallbackSaturation : 0,
                brightness: brightest
            )
            return
        }

        let sector: Double
        if brightest == color.red {
            sector = (color.green - color.blue) / chroma
        } else if brightest == color.green {
            sector = 2 + (color.blue - color.red) / chroma
        } else {
            sector = 4 + (color.red - color.green) / chroma
        }

        self.init(
            hue: (sector < 0 ? sector + 6 : sector) / 6,
            saturation: chroma / brightest,
            brightness: brightest
        )
    }

    var color: TodoColor {
        let scaledHue = hue * 6
        let sector = Int(scaledHue) % 6
        let fraction = scaledHue - floor(scaledHue)
        let darkest = brightness * (1 - saturation)
        let fading = brightness * (1 - saturation * fraction)
        let rising = brightness * (1 - saturation * (1 - fraction))

        switch sector {
        case 0: return TodoColor(red: brightness, green: rising, blue: darkest)
        case 1: return TodoColor(red: fading, green: brightness, blue: darkest)
        case 2: return TodoColor(red: darkest, green: brightness, blue: rising)
        case 3: return TodoColor(red: darkest, green: fading, blue: brightness)
        case 4: return TodoColor(red: rising, green: darkest, blue: brightness)
        default: return TodoColor(red: brightness, green: darkest, blue: fading)
        }
    }
}

@MainActor
final class TodoStore: ObservableObject {
    static let opacityRange = 0.2...1.0
    static let defaultBackgroundColor = TodoColor(red: 0.055, green: 0.095, blue: 0.10)
    static let defaultAccentColor = TodoColor(red: 0.67, green: 0.95, blue: 0.79)
    private static let defaultBackgroundHSB = TodoHSB(color: defaultBackgroundColor)
    private static let defaultAccentHSB = TodoHSB(color: defaultAccentColor)
    private static let defaultOpacity = 0.72

    private enum Key {
        static let items = "todo.items"
        static let opacity = "todo.opacity"
        static let usesGlass = "todo.usesGlass"
        static let backgroundHSB = "todo.backgroundHSB"
        static let accentHSB = "todo.accentHSB"
        static let legacyBackgroundColor = "todo.backgroundColor"
        static let legacyAccentColor = "todo.accentColor"
    }

    private let defaults: UserDefaults

    @Published private(set) var items: [TodoItem] {
        didSet {
            if let data = try? JSONEncoder().encode(items) {
                defaults.set(data, forKey: Key.items)
            }
        }
    }

    @Published var opacity: Double {
        didSet {
            let value = Self.clampOpacity(opacity)
            if opacity != value {
                opacity = value
            }
            defaults.set(value, forKey: Key.opacity)
        }
    }

    @Published var usesGlass: Bool {
        didSet { defaults.set(usesGlass, forKey: Key.usesGlass) }
    }

    @Published var backgroundHSB: TodoHSB {
        didSet { Self.saveHSB(backgroundHSB, in: defaults, forKey: Key.backgroundHSB) }
    }

    @Published var accentHSB: TodoHSB {
        didSet { Self.saveHSB(accentHSB, in: defaults, forKey: Key.accentHSB) }
    }

    var backgroundColor: TodoColor {
        get { backgroundHSB.color }
        set {
            backgroundHSB = TodoHSB(
                color: newValue,
                fallbackHue: backgroundHSB.hue,
                fallbackSaturation: backgroundHSB.saturation
            )
        }
    }

    var accentColor: TodoColor {
        get { accentHSB.color }
        set {
            accentHSB = TodoHSB(
                color: newValue,
                fallbackHue: accentHSB.hue,
                fallbackSaturation: accentHSB.saturation
            )
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.items),
           let savedItems = try? JSONDecoder().decode([TodoItem].self, from: data) {
            items = savedItems
        } else {
            items = []
        }
        let savedOpacity = defaults.object(forKey: Key.opacity) as? Double
        opacity = Self.clampOpacity(savedOpacity ?? Self.defaultOpacity)
        usesGlass = defaults.object(forKey: Key.usesGlass) as? Bool ?? true
        backgroundHSB = Self.loadHSB(
            from: defaults,
            forKey: Key.backgroundHSB,
            legacyKey: Key.legacyBackgroundColor
        ) ?? Self.defaultBackgroundHSB
        accentHSB = Self.loadHSB(
            from: defaults,
            forKey: Key.accentHSB,
            legacyKey: Key.legacyAccentColor
        ) ?? Self.defaultAccentHSB
    }

    func resetColors() {
        backgroundHSB = Self.defaultBackgroundHSB
        accentHSB = Self.defaultAccentHSB
    }

    func add(title: String, deadline: Date) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, deadline.timeIntervalSinceReferenceDate.isFinite else { return }
        items.append(TodoItem(id: UUID(), title: title, deadline: deadline, isCompleted: false))
    }

    func update(id: UUID, title: String, deadline: Date) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, deadline.timeIntervalSinceReferenceDate.isFinite,
              let index = items.firstIndex(where: { $0.id == id }) else { return }

        items[index] = TodoItem(
            id: id,
            title: title,
            deadline: deadline,
            isCompleted: items[index].isCompleted
        )
    }

    func toggle(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isCompleted.toggle()
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
    }

    private static func loadHSB(
        from defaults: UserDefaults,
        forKey key: String,
        legacyKey: String
    ) -> TodoHSB? {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: key),
           let saved = try? decoder.decode(TodoHSB.self, from: data) {
            return saved
        }
        guard let data = defaults.data(forKey: legacyKey),
              let legacyColor = try? decoder.decode(TodoColor.self, from: data) else { return nil }
        let migrated = TodoHSB(color: legacyColor)
        saveHSB(migrated, in: defaults, forKey: key)
        return migrated
    }

    private static func saveHSB(_ color: TodoHSB, in defaults: UserDefaults, forKey key: String) {
        if let data = try? JSONEncoder().encode(color) {
            defaults.set(data, forKey: key)
        }
    }

    private static func clampOpacity(_ value: Double) -> Double {
        guard !value.isNaN else { return defaultOpacity }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }
}
