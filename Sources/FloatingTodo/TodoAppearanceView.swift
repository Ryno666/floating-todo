import SwiftUI

struct TodoAppearanceView: View {
    @ObservedObject var store: TodoStore
    let primaryInk: Color
    let secondaryInk: Color
    let outline: Color
    let controlSurface: Color

    @State private var colorTarget: ColorTarget?

    private enum ColorTarget: String, CaseIterable {
        case background = "底色"
        case accent = "主题色"
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            recommendedPalettes
            customColors
            surfaceControls
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(primaryInk)
        .controlSize(.small)
        .padding(12)
        .background(controlSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var recommendedPalettes: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("推荐配色")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("恢复默认颜色", action: store.resetColors)
                    .buttonStyle(PanelButtonStyle())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(secondaryInk)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(RecommendedPalette.all) { palette in
                    presetButton(palette)
                }
            }
        }
    }

    private var customColors: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                ForEach(ColorTarget.allCases, id: \.self) { target in
                    colorButton(target)
                }
            }
            percentageSlider("主题色饱和度", value: component($store.accentHSB, \.saturation))

            if let colorTarget {
                colorEditor(colorTarget)
            }
        }
    }

    private var surfaceControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            percentageSlider("背景不透明度", value: $store.opacity, in: TodoStore.opacityRange)

            Toggle(isOn: $store.usesGlass) {
                Text("毛玻璃")
                    .foregroundStyle(secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
        }
    }

    private func presetButton(_ palette: RecommendedPalette) -> some View {
        let isSelected = store.backgroundColor.hexValue == palette.background.hexValue
            && store.accentColor.hexValue == palette.accent.hexValue

        return Button {
            store.backgroundHSB = TodoHSB(color: palette.background)
            store.accentHSB = TodoHSB(color: palette.accent)
        } label: {
            VStack(spacing: 3) {
                palettePreview(palette, isSelected: isSelected)
                    .accessibilityHidden(true)
                Text(palette.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? primaryInk : secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(3)
            .frame(maxWidth: .infinity)
            .background(outline.opacity(isSelected ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func palettePreview(_ palette: RecommendedPalette, isSelected: Bool) -> some View {
        let accent = palette.accent.swiftUIColor
        let card = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return HStack(spacing: 4) {
            Circle()
                .strokeBorder(accent, lineWidth: 1.2)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(accent).frame(width: 21, height: 2)
                Capsule().fill(accent.opacity(0.45)).frame(width: 13, height: 2)
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .background(.black.opacity(0.75), in: Circle())
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(palette.background.swiftUIColor, in: card)
        .overlay { card.strokeBorder(outline.opacity(0.18)) }
    }

    private func colorButton(_ target: ColorTarget) -> some View {
        let isSelected = colorTarget == target
        let color = target == .background ? store.backgroundColor : store.accentColor

        return Button {
            colorTarget = isSelected ? nil : target
        } label: {
            HStack(spacing: 6) {
                Text(target.rawValue)
                Spacer(minLength: 1)
                Capsule()
                    .fill(color.swiftUIColor)
                    .overlay {
                        Capsule().strokeBorder(outline.opacity(0.28))
                    }
                    .frame(width: 21, height: 11)
                Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(secondaryInk)
            }
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(outline.opacity(isSelected ? 0.12 : 0.045), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelButtonStyle())
        .accessibilityLabel("选择\(target.rawValue)")
        .accessibilityValue(color.hexValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorEditor(_ target: ColorTarget) -> some View {
        let color = target == .background ? $store.backgroundHSB : $store.accentHSB
        let swatch = color.wrappedValue.color
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("色盘")
                    .fontWeight(.semibold)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(swatch.swiftUIColor)
                        .overlay { Circle().strokeBorder(outline.opacity(0.22)) }
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                    Text(swatch.hexValue)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(secondaryInk)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(outline.opacity(0.07), in: Capsule())
            }
            HueSaturationPalette(color: color, label: "选择\(target.rawValue)的色盘")
                .frame(height: 74)
            if target == .background {
                percentageSlider("底色饱和度", value: component(color, \.saturation))
            }
            percentageSlider("亮度", value: component(color, \.brightness))
        }
    }

    private func percentageSlider(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...1
    ) -> some View {
        let percentage = value.wrappedValue.formatted(.percent.precision(.fractionLength(0)))
        return HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(secondaryInk)
                .frame(width: 76, alignment: .leading)
                .accessibilityHidden(true)
            Slider(value: value, in: range, step: 0.01)
                .accessibilityLabel(label)
                .accessibilityValue(percentage)
            Text(percentage)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .frame(width: 33, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private func component(_ selection: Binding<TodoHSB>, _ key: KeyPath<TodoHSB, Double>) -> Binding<Double> {
        Binding {
            selection.wrappedValue[keyPath: key]
        } set: { value in
            let color = selection.wrappedValue
            selection.wrappedValue = TodoHSB(
                hue: color.hue,
                saturation: key == \.saturation ? value : color.saturation,
                brightness: key == \.brightness ? value : color.brightness
            )
        }
    }
}

private struct HueSaturationPalette: View {
    @Binding var color: TodoHSB
    let label: String

    private let spectrum: [Color] = (0...6).map {
        Color(hue: Double($0) / 6, saturation: 1, brightness: 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let inset = 7.0
            let width = max(1, size.width - inset * 2)
            let height = max(1, size.height - inset * 2)
            let horizontalInset = inset / max(1, size.width)
            let verticalInset = inset / max(1, size.height)
            let frame = RoundedRectangle(cornerRadius: 9, style: .continuous)
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: spectrum,
                    startPoint: UnitPoint(x: horizontalInset, y: 0.5),
                    endPoint: UnitPoint(x: 1 - horizontalInset, y: 0.5)
                )
                LinearGradient(
                    colors: [.white, .white.opacity(0)],
                    startPoint: UnitPoint(x: 0.5, y: verticalInset),
                    endPoint: UnitPoint(x: 0.5, y: 1 - verticalInset)
                )
                Circle()
                    .fill(color.color.swiftUIColor)
                    .overlay {
                        Circle().strokeBorder(.black.opacity(0.7), lineWidth: 3)
                        Circle().inset(by: 1).strokeBorder(.white, lineWidth: 1.5)
                    }
                    .frame(width: 14, height: 14)
                    .position(x: inset + color.hue * width, y: inset + color.saturation * height)
            }
            .clipShape(frame)
            .overlay { frame.strokeBorder(.black.opacity(0.18)).allowsHitTesting(false) }
            .contentShape(frame)
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                color = TodoHSB(
                    hue: (event.location.x - inset) / width,
                    saturation: (event.location.y - inset) / height,
                    brightness: color.brightness
                )
            })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(color.color.hexValue)
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / 36
            let shiftedHue: Double
            switch direction {
            case .increment: shiftedHue = color.hue + step
            case .decrement: shiftedHue = color.hue - step
            @unknown default: return
            }
            color = TodoHSB(
                hue: shiftedHue - floor(shiftedHue),
                saturation: color.saturation,
                brightness: color.brightness
            )
        }
    }
}

private struct RecommendedPalette: Identifiable {
    let name: String
    let background: TodoColor
    let accent: TodoColor

    var id: String { name }

    init(_ name: String, _ background: UInt32, _ accent: UInt32) {
        self.name = name
        self.background = TodoColor(hex: background)
        self.accent = TodoColor(hex: accent)
    }

    static let all = [
        RecommendedPalette("暖白玫瑰", 0xF7EEE3, 0xB96E72),
        RecommendedPalette("雾蓝", 0xEAF1FA, 0x4266AD),
        RecommendedPalette("茶绿", 0xEFF3E7, 0x59754D),
        RecommendedPalette("薄荷夜", 0x101F23, 0xA1DEC9),
        RecommendedPalette("暮紫", 0x252033, 0xBDAAEB),
        RecommendedPalette("深海", 0x13263B, 0x8EBDF3)
    ]
}

extension TodoColor {
    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    fileprivate var hexValue: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    fileprivate init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255
        )
    }
}
