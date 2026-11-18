import AppKit
import SwiftUI

private let panelShape = RoundedRectangle(cornerRadius: 24, style: .continuous)
private let resizeHandleSize: CGFloat = 28
private let resizeBorderWidth: CGFloat = 7

struct TodoPanelView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var resizeState: WindowResizeState
    let onHide: () -> Void

    @State private var showingAppearance = false
    @State private var showingEditor = false
    @State private var hoveredRow: UUID?
    @State private var hoveredIcon: String?
    @State private var editingID: UUID?
    @State private var draftTitle = ""
    @State private var draftDeadline = Date()
    @FocusState private var titleIsFocused: Bool

    private var pending: [TodoItem] {
        store.items.filter { !$0.isCompleted }.sorted { $0.deadline < $1.deadline }
    }

    private var completed: [TodoItem] {
        store.items.filter(\.isCompleted).sorted { $0.deadline > $1.deadline }
    }

    private var lightBackground: Bool { store.backgroundColor.luminance > 0.24 }
    private var panelInk: Color { store.backgroundColor.swiftUIColor }
    private var accent: Color { store.accentColor.swiftUIColor }
    private var accentInk: Color { store.accentColor.luminance > 0.179 ? .black : .white }
    private var primaryInk: Color {
        lightBackground ? Color(red: 0.06, green: 0.08, blue: 0.09)
            : Color(red: 0.96, green: 0.98, blue: 0.97)
    }
    private var secondaryInk: Color {
        lightBackground ? Color(red: 0.18, green: 0.22, blue: 0.23)
            : Color(red: 0.77, green: 0.82, blue: 0.81)
    }
    private var overdueInk: Color {
        lightBackground ? Color(red: 0.53, green: 0.10, blue: 0.09)
            : Color(red: 1, green: 0.72, blue: 0.65)
    }
    private var outline: Color { lightBackground ? .black : .white }
    private var panelBorderStyle: LinearGradient {
        LinearGradient(
            colors: [outline.opacity(lightBackground ? 0.19 : 0.3), outline.opacity(0.06), outline.opacity(0.16)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    private var resizeHandleAlignment: Alignment {
        resizeState.corner == .bottomLeft ? .bottomLeading : .bottomTrailing
    }

    private var controlSurface: Color {
        (lightBackground ? Color.white : Color.black)
            .opacity(0.15 + max(0, 0.65 - store.opacity) * 0.95)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            divider
                .padding(.top, 14)

            if showingAppearance || showingEditor || !store.items.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        if showingAppearance {
                            TodoAppearanceView(
                                store: store,
                                primaryInk: primaryInk,
                                secondaryInk: secondaryInk,
                                outline: outline,
                                controlSurface: controlSurface
                            )
                            .padding(.top, 16)
                        }

                        if showingEditor {
                            editor
                        } else if !store.items.isEmpty {
                            taskList
                        }
                    }
                    .padding(.bottom, 8)
                }
            } else {
                emptyList
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 17)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBackground)
        .overlay(alignment: resizeHandleAlignment) {
            resizeHandle
        }
        .environment(\.colorScheme, lightBackground ? .light : .dark)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .tint(accent)
    }

    private var panelBackground: some View {
        ZStack {
            if store.usesGlass {
                GlassBackdrop()
                    .opacity(1 - store.opacity)
            }

            panelInk.opacity(store.opacity)
            if store.usesGlass {
                LinearGradient(
                    colors: [.white.opacity(0.09 * store.opacity), .clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            }
        }
        .clipShape(panelShape)
        .overlay {
            panelShape.strokeBorder(panelBorderStyle, lineWidth: 1)
            .overlay {
                panelShape.strokeBorder(Color(white: 0.973), lineWidth: resizeBorderWidth)
                    .mask(alignment: resizeHandleAlignment) {
                        ResizeGripMask(corner: resizeState.corner)
                            .stroke(.white, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .frame(width: resizeHandleSize, height: resizeHandleSize)
                    }
                    .compositingGroup()
                    .shadow(
                        color: .black.opacity(0.34),
                        radius: 6,
                        x: resizeState.corner == .bottomLeft ? 1.8 : -1.8,
                        y: -2.5
                    )
                    .clipShape(panelShape)
            }
            .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            HStack {
                Text("待办")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(primaryInk)
                    .shadow(color: controlSurface, radius: 1.5, y: 1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 34)
            .overlay(WindowDragRegion())

            Button {
                prepareEditor(for: nil)
            } label: {
                Label("新建", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(accent, in: Capsule())
                    .foregroundStyle(accentInk)
            }
            .buttonStyle(PanelButtonStyle())
            .disabled(showingEditor)
            .keyboardShortcut("n", modifiers: .command)

            HStack(spacing: 1) {
                iconButton(
                    symbol: "slider.horizontal.3",
                    label: "外观设置",
                    isSelected: showingAppearance
                ) {
                    showingAppearance.toggle()
                }

                iconButton(symbol: "minus", label: "隐藏待办") {
                    onHide()
                }
            }
            .padding(2)
            .background(controlSurface, in: Capsule())
        }
    }

    private var resizeHandle: some View {
        WindowResizeRegion(corner: resizeState.corner)
            .frame(width: resizeHandleSize, height: resizeHandleSize)
            .help("拖动调整窗口大小")
            .accessibilityHidden(true)
    }

    private var emptyList: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(secondaryInk)
                .frame(width: 43, height: 43)
                .background(controlSurface, in: Circle())
                .overlay { Circle().strokeBorder(outline.opacity(0.12)) }
                .accessibilityHidden(true)
            Text("还没有待办")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondaryInk)
                .shadow(color: controlSurface, radius: 2, y: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var taskList: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 18) {
                if !pending.isEmpty {
                    taskSection("待完成", items: pending, now: context.date, showsDeadline: true)
                }
                if !completed.isEmpty {
                    taskSection("已完成", items: completed, now: context.date, showsDeadline: pending.isEmpty)
                }
            }
            .padding(.top, 16)
        }
    }

    private func taskSection(_ label: String, items: [TodoItem], now: Date, showsDeadline: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        return VStack(spacing: 7) {
            HStack(spacing: 6) {
                Text(label)
                    .accessibilityAddTraits(.isHeader)
                Text(items.count, format: .number)
                    .monospacedDigit()
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(outline.opacity(0.08), in: Capsule())
                Spacer()
                if showsDeadline {
                    Text("截止时间")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(secondaryInk)
            .shadow(color: controlSurface, radius: 1.5, y: 1)
            .padding(.leading, 3)
            .padding(.trailing, 12)

            VStack(spacing: 0) {
                ForEach(items) { item in
                    taskRow(item, now: now)
                    if item.id != items.last?.id {
                        divider
                            .padding(.leading, 43)
                            .padding(.trailing, 12)
                    }
                }
            }
            .background(controlSurface, in: shape)
            .clipShape(shape)
        }
    }

    private func taskRow(_ item: TodoItem, now: Date) -> some View {
        let isOverdue = !item.isCompleted && item.deadline <= now

        return HStack(spacing: 1) {
            Button {
                store.toggle(id: item.id)
            } label: {
                ZStack {
                    if item.isCompleted {
                        Circle().fill(accent)
                        Circle().strokeBorder(outline.opacity(0.20))
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(accentInk)
                    } else {
                        Circle().strokeBorder(secondaryInk.opacity(0.85), lineWidth: 1.25)
                    }
                }
                .frame(width: 17, height: 17)
                .frame(width: 37, height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(PanelButtonStyle())
            .help(item.isCompleted ? "恢复为待完成" : "标记为完成")
            .accessibilityLabel(item.isCompleted ? "恢复待完成：\(item.title)" : "完成：\(item.title)")

            Button {
                prepareEditor(for: item)
            } label: {
                HStack(spacing: 10) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? secondaryInk : primaryInk)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.deadline, format: .verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)", locale: .current, timeZone: .current, calendar: .current))
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(secondaryInk)
                        Text(item.deadline, format: .verbatim("\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)", locale: .current, timeZone: .current, calendar: .current))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(isOverdue ? overdueInk : item.isCompleted ? secondaryInk : primaryInk)
                    }
                    .fixedSize()
                }
                .frame(maxWidth: .infinity, minHeight: 51, alignment: .leading)
                .padding(.trailing, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PanelButtonStyle())
            .help(isOverdue ? "已逾期 · 点击编辑" : "点击编辑")
            .accessibilityHint(isOverdue ? "已逾期，点击编辑待办" : "点击编辑待办")
        }
        .padding(.leading, 5)
        .background(outline.opacity(hoveredRow == item.id ? 0.06 : 0))
        .onHover { hovering in
            if hovering || hoveredRow == item.id {
                hoveredRow = hovering ? item.id : nil
            }
        }
        .contextMenu {
            Button("编辑待办") {
                prepareEditor(for: item)
            }
            Button("删除待办", role: .destructive) {
                store.remove(id: item.id)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(editingID == nil ? "新建待办" : "编辑待办")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            TextField("待办内容", text: $draftTitle)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .padding(9)
                .background(outline.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(titleIsFocused ? accent : outline.opacity(0.14))
                        .allowsHitTesting(false)
                }
                .focused($titleIsFocused)
                .onAppear { titleIsFocused = true }
                .onSubmit(saveDraft)

            HStack(spacing: 12) {
                Text("截止时间")
                    .foregroundStyle(secondaryInk)
                Spacer()
                DatePicker(
                    "截止时间",
                    selection: $draftDeadline,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .fixedSize()
                .environment(\.locale, Locale(identifier: "en_GB"))
            }

            HStack(spacing: 12) {
                if let editingID {
                    Button("删除", role: .destructive) {
                        store.remove(id: editingID)
                        closeEditor()
                    }
                    .foregroundStyle(overdueInk)
                    .buttonStyle(PanelButtonStyle())
                }

                Spacer()

                Button("取消", action: closeEditor)
                    .foregroundStyle(secondaryInk)
                    .buttonStyle(PanelButtonStyle())
                    .keyboardShortcut(.cancelAction)

                Button(action: saveDraft) {
                    Text("保存")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accentInk)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(PanelButtonStyle())
                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(primaryInk)
        .padding(14)
        .background(controlSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .padding(.top, 16)
    }

    private var divider: some View {
        Rectangle()
            .fill(outline.opacity(0.13))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }

    private func iconButton(
        symbol: String,
        label: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 27, height: 26)
                .foregroundStyle(isSelected ? primaryInk : secondaryInk)
                .background(outline.opacity(isSelected ? 0.13 : hoveredIcon == symbol ? 0.08 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PanelButtonStyle())
        .accessibilityLabel(label)
        .help(label)
        .onHover { hovering in
            if hovering || hoveredIcon == symbol {
                hoveredIcon = hovering ? symbol : nil
            }
        }
    }

    private func prepareEditor(for item: TodoItem?) {
        editingID = item?.id
        draftTitle = item?.title ?? ""
        let now = Date()
        let nextHour = Calendar.current.dateInterval(of: .hour, for: now)?.end
        draftDeadline = item?.deadline ?? nextHour ?? now.addingTimeInterval(3600)
        showingAppearance = false
        showingEditor = true
    }

    private func saveDraft() {
        guard !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let editingID {
            store.update(id: editingID, title: draftTitle, deadline: draftDeadline)
        } else {
            store.add(title: draftTitle, deadline: draftDeadline)
        }
        closeEditor()
    }

    private func closeEditor() {
        titleIsFocused = false
        showingEditor = false
        editingID = nil
    }
}

private struct ResizeGripMask: Shape {
    let corner: WindowResizeCorner

    func path(in rect: CGRect) -> Path {
        func point(_ sideInset: CGFloat, _ bottomInset: CGFloat) -> CGPoint {
            CGPoint(
                x: corner == .bottomLeft ? rect.minX + sideInset : rect.maxX - sideInset,
                y: rect.maxY - bottomInset
            )
        }

        // Keep the thicker border on the curved part of the corner.
        var path = Path()
        path.move(to: point(5.7, 19.2))
        path.addCurve(to: point(19.2, 5.7), control1: point(7.9, 12.9), control2: point(12.9, 7.9))
        return path
    }
}

private extension TodoColor {
    var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

struct PanelButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.68 : 1) : 0.45)
    }
}

private struct GlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
