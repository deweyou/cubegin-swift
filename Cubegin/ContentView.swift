import SwiftUI
import WebKit

struct ContentView: View {
    @Bindable var model: TimerModel
    let isTimerActive: Bool
    @AppStorage(TimerModel.startDelayKey) private var startDelayTenths = TimerModel.defaultStartDelayTenths
    @FocusState private var hasTimerKeyboardFocus: Bool
    @State private var idlePageFrame: CGRect?
    private var isTiming: Bool { model.started != nil }
    @State private var showsProjectList = false
    @State private var solveToDelete: Solve?
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }
    private let controlIconSize: CGFloat = 20
    private let controlRowHeight: CGFloat = 44
    private let compactControlSize: CGFloat = 32
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .footnote) private var standardMegaminxFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .title3) private var scrambleFontSize: CGFloat = 20

    // The native iPad TabView uses the top bar in regular-width layouts.
    private var usesTopNavigation: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                NavigationStack {
                    page
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(isTiming ? .hidden : .visible, for: .navigationBar)
                        .toolbar {
                            if !usesTopNavigation {
                                ToolbarItem(placement: .topBarLeading) {
                                    // Keep the icon and text together as custom toolbar content.
                                    HStack(spacing: 0) {
                                        projectMenu
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                    .disabled(model.busy || model.started != nil)
                                }
                                .sharedBackgroundVisibility(.hidden)
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                trailingControls
                                    .padding(.trailing, usesTopNavigation ? 20 : 0)
                                    .disabled(model.busy || model.started != nil)
                            }
                            .sharedBackgroundVisibility(.hidden)
                        }
                }
            } else {
                page
            }
        }
        .focusable(isTimerActive)
        .focusEffectDisabled()
        .focused($hasTimerKeyboardFocus)
        .onKeyPress(.space, phases: [.down, .up, .repeat]) { press in
            guard isTimerActive, !showsProjectList, solveToDelete == nil else { return .ignored }
            switch press.phase {
            case .down: model.press(.keyboard, delayTenths: startDelayTenths)
            case .up: model.release(.keyboard)
            default: break
            }
            return .handled
        }
        .onChange(of: isTimerActive, initial: true) { _, active in
            hasTimerKeyboardFocus = active
            if !active { model.cancelPress() }
        }
        .onChange(of: showsProjectList) { _, isShowing in
            if isShowing { model.cancelPress() }
            else if isTimerActive { hasTimerKeyboardFocus = true }
        }
        .alert(language.text("确定删除这条成绩吗？", "Delete this solve?"), isPresented: Binding(
            get: { solveToDelete != nil },
            set: { if !$0 { solveToDelete = nil } }
        ), presenting: solveToDelete) { solve in
            Button(language.text("取消", "Cancel"), role: .cancel) {}
            Button(language.text("删除", "Delete"), role: .destructive) {
                guard model.lastSolve?.id == solve.id else { return }
                model.deleteLastSolve()
            }
        }
        .onChange(of: hasTimerKeyboardFocus) { _, focused in
            if !focused { model.cancelPress(.keyboard) }
        }
#if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("--measure-picker") {
                measurePickerWidths()
            }
        }
#endif
    }
    private var page: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            // The Duo outer display reserves horizontal space for its side rail.
            let hasSideRail = UIDevice.current.userInterfaceIdiom == .phone
                && geometry.size.height > geometry.size.width
                && max(insets.leading, insets.trailing) > 24
            let diagramBottomPadding = hasSideRail ? 18 - insets.bottom : 12
            let frame = geometry.frame(in: .global)
            page(frame: frame, diagramBottomPadding: diagramBottomPadding)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { measuredFrame in
                    if !isTiming { idlePageFrame = measuredFrame }
                }
        }
    }

    private func page(frame: CGRect, diagramBottomPadding: CGFloat) -> some View {
        let width = frame.width
        let height = frame.height
        let timerFrame = (isTiming ? idlePageFrame : nil) ?? frame
        let contentWidth = max(1, min(width, 880) - 48)
        let timerFontSize: CGFloat = timerFrame.width > 600 ? 110 : 76
        let timerNumberHeight = timerFontSize * 1.2
        let showsControlsInPage = usesTopNavigation || UIDevice.current.userInterfaceIdiom != .pad
        let controlsHeight = showsControlsInPage ? controlRowHeight : 0
        let topClearance: CGFloat = 8
        let controlSpacing: CGFloat = showsControlsInPage ? 8 : 0
        let formulaHeight = max(1, min(height * 0.3,
            height / 2 - timerNumberHeight / 2 - controlsHeight - controlSpacing - topClearance - 8))
        let summaryWidth = max(0, (contentWidth - 12) / 3.2)
        let diagramClearance: CGFloat = model.lastSolve == nil ? 68 : max(68, 14 + compactControlSize + diagramBottomPadding + 8)
        let diagramHeight = max(0, min(180, height / 2 - timerNumberHeight / 2 - diagramClearance))

        return ZStack {
            TimerTouchSurface(
                onDown: {
                    guard isTimerActive, !showsProjectList, solveToDelete == nil else { return }
                    model.press(.touch, delayTenths: startDelayTenths)
                },
                onUp: { model.release(.touch) },
                onCancel: { model.cancelPress(.touch) }
            )
            .frame(width: width, height: height)
            .frame(width: contentWidth)
            .accessibilityHidden(true)

            if !isTiming {
                VStack(spacing: 0) {
                    if usesTopNavigation {
                        projectMenu
                            .frame(maxWidth: .infinity)
                            .frame(height: controlRowHeight)
                            .disabled(model.busy || model.started != nil)
                    } else if showsControlsInPage {
                        HStack(spacing: 0) {
                            projectMenu
                            Spacer(minLength: 12)
                            trailingControls
                        }
                        .frame(height: controlRowHeight)
                        .disabled(model.busy || model.started != nil)
                    }
                    Group {
                        if model.busy && model.scramble == nil {
                            ProgressView(language.text("计算中…", "Generating…"))
                        } else {
                            scrambleFormula(width: contentWidth)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: formulaHeight)
                    .padding(.top, controlSpacing)
                }
                .padding(.top, topClearance)
                .frame(height: height, alignment: .top)
            }

            if !isTiming, let svg = model.scramble?.svg, diagramHeight > 0 {
                HStack(spacing: 12) {
                    // Reserve the leading column for the results summary.
                    Color.clear
                        .frame(width: summaryWidth, height: diagramHeight)
                        .accessibilityHidden(true)
                    SVGView(svg: svg)
                        .frame(maxWidth: .infinity)
                        .frame(height: diagramHeight)
                        .accessibilityLabel(language.text("当前打乱状态图", "Current scramble diagram"))
                }
                .padding(.bottom, diagramBottomPadding)
                .frame(height: height, alignment: .bottom)
            }

            timerDisplay(fontSize: timerFontSize, numberHeight: timerNumberHeight)
                .frame(width: max(1, min(timerFrame.width, 880) - 48))
                .offset(x: timerFrame.midX - frame.midX, y: timerFrame.midY - frame.midY)
        }
        .frame(height: height)
        .padding(.horizontal, 24)
        .frame(maxWidth: 880)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Color.cyan.opacity(0.14), Color(.systemBackground), Color.indigo.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
        }
    }

    private func timerDisplay(fontSize: CGFloat, numberHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            // Mirror the reserved action row so the digits stay centered.
            Color.clear.frame(height: compactControlSize)
            TimelineView(.animation(minimumInterval: 0.03, paused: !isTiming)) { _ in
                let duration = model.started.map { $0.duration(to: .now) }
                let solve = model.lastSolve
                let seconds = duration.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 } ?? solve?.resultSeconds ?? 0
                let readout = solve?.penalty == .dnf
                    ? AttributedString("DNF", attributes: AttributeContainer.font(.system(size: fontSize, design: .rounded)))
                    : timerReadout(seconds, fontSize: fontSize)
                Text(readout)
                    .foregroundStyle(model.isReady ? Color.green : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 12)
                    .frame(height: numberHeight)
                    .accessibilityLabel(isTiming ? language.text("停止计时", "Stop timer") : language.text("开始计时", "Start timer"))
                    .accessibilityValue(solve?.resultText ?? TimerModel.format(seconds))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.activateAccessibleTimer() }
            }
            .allowsHitTesting(false)

            Group {
                if !isTiming, let solve = model.lastSolve {
                    HStack(spacing: 10) {
                        penaltyButton("+2", label: language.text("加两秒", "Add two seconds"), penalty: .plusTwo, selected: solve.penalty)
                        penaltyButton("DNF", label: language.text("标记成绩无效", "Mark as did not finish"), penalty: .dnf, selected: solve.penalty)
                        Button(role: .destructive) {
                            model.cancelPress()
                            solveToDelete = solve
                        } label: {
                            Image(systemName: "trash")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(Color.secondary)
                                .modifier(CompactControlTarget(size: compactControlSize))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(language.text("删除这条成绩", "Delete this solve"))
                    }
                } else {
                    Color.clear
                        .allowsHitTesting(false)
                }
            }
            .frame(height: compactControlSize)
        }
    }

    private func penaltyButton(_ title: String, label: String, penalty: SolvePenalty, selected: SolvePenalty?) -> some View {
        Button {
            model.togglePenalty(penalty)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(selected == penalty ? Color.accentColor : Color.secondary)
                .modifier(CompactControlTarget(size: compactControlSize))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected == penalty ? .isSelected : [])
    }

    private func timerReadout(_ seconds: Double, fontSize: CGFloat) -> AttributedString {
        let parts = TimerModel.displayParts(seconds)
        var readout = AttributedString()
        for (index, part) in parts.enumerated() {
            let isMilliseconds = index == parts.count - 1
            let size = isMilliseconds ? fontSize * 0.55 : fontSize
            var run = AttributedString(part)
            run.font = .system(size: size, weight: isMilliseconds ? .bold : .regular, design: .rounded).monospacedDigit()
            readout.append(run)
        }
        return readout
    }

    private func scrambleFormula(width: CGFloat) -> some View {
        let algorithm = model.scramble?.algorithm ?? language.text("准备你的下一次挑战", "Ready for your next solve")
        let preservesMegaminxRows = model.mode == .standard && model.event == "minx"
        var fontSize = preservesMegaminxRows ? standardMegaminxFontSize : scrambleFontSize
        if preservesMegaminxRows, model.scramble != nil {
            let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let widestLine = algorithm.components(separatedBy: .newlines).map { line in
                (line as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0
            if widestLine > width - 2 {
                fontSize *= max(1, width - 2) / widestLine
            }
        }
        let minimumSize = min(fontSize, 1)
        let sizes = Array(stride(from: fontSize, to: minimumSize, by: -0.5)) + [minimumSize]
        return ViewThatFits(in: .vertical) {
            ForEach(sizes, id: \.self) { size in
                Text(algorithm)
                    .font(.system(size: size, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .lineSpacing((preservesMegaminxRows ? 4 : 7) * size / fontSize)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
            }
        }
    }

    private var projectMenu: some View {
        projectButton(event: model.event, language: language, large: usesTopNavigation) {
            showsProjectList = true
        }
        .popover(isPresented: $showsProjectList, arrowEdge: .top) {
            List {
                if model.mode == .standard {
                    ForEach(ScrambleCatalog.standard, content: projectRow)
                } else {
                    ForEach(ScrambleCatalog.trainingGroups(in: language), id: \.self) { group in
                        DisclosureGroup(group) {
                            ForEach(ScrambleCatalog.training.filter { $0.group(in: language) == group }, content: projectRow)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .frame(width: 300, height: 400)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func projectRow(_ choice: ScrambleChoice) -> some View {
        Button {
            showsProjectList = false
            model.eventSelection = choice.id
        } label: {
            HStack {
                Text(choice.title(in: language))
                Spacer()
                if choice.id == model.event {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice.id == model.event ? .isSelected : [])
    }

    private func projectButton(event: String, language: AppLanguage, large: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            projectMenuLabel(event: event, language: language, large: large)
        }
        .buttonStyle(.plain)
        .controlSize(large ? .regular : .small)
        .accessibilityLabel(language.text("打乱项目", "Event"))
        .accessibilityValue(ScrambleCatalog.title(event, in: language))
    }

    private func projectMenuLabel(event: String, language: AppLanguage, large: Bool) -> some View {
        let iconID = String(event.prefix { $0 != "." })
        return HStack(spacing: 6) {
            Image("Event-\(iconID)")
                .resizable()
                .scaledToFit()
                .frame(width: controlIconSize, height: controlIconSize)
                .accessibilityHidden(true)
            if let title = ScrambleCatalog.trainingSelectionTitle(event, in: language) {
                Text(title).lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
        }
        .font(large ? .body.weight(.medium) : .subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .frame(minWidth: 44, minHeight: controlRowHeight, alignment: .leading)
        .contentShape(Rectangle())
    }

#if DEBUG
    // Measure each production button without a constrained parent.
    @MainActor
    private func measurePickerWidths() {
        func width<V: View>(_ view: V, language: AppLanguage) -> CGFloat {
            let host = UIHostingController(rootView: view
                .fixedSize(horizontal: true, vertical: true)
                .environment(\.locale, language.locale)
                .dynamicTypeSize(.large))
            return host.sizeThatFits(in: CGSize(width: 2_000, height: 100)).width
        }
        let choices = ScrambleCatalog.standard + ScrambleCatalog.training
        let rows = AppLanguage.allCases.flatMap { language in
            choices.map { choice in
                ["language": language.rawValue, "id": choice.id,
                 "title": ScrambleCatalog.trainingSelectionTitle(choice.id, in: language) ?? choice.title(in: language),
                 "compactPicker": width(projectButton(event: choice.id, language: language, large: false, action: {}), language: language),
                 "regularPicker": width(projectButton(event: choice.id, language: language, large: true, action: {}), language: language)] as [String: Any]
            }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL.documentsDirectory.appending(path: "picker-widths.json"), options: .atomic)
        } catch {
            assertionFailure("Could not save Picker measurements: \(error)")
        }
    }
#endif
    private var trailingControls: some View {
        HStack(spacing: 8) {
            trainingButton
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .frame(width: controlIconSize, height: controlIconSize)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: controlRowHeight)
                .accessibilityHidden(true)
        }
    }

    private var trainingButton: some View {
        Button {
            model.mode = model.mode == .training ? .standard : .training
        } label: {
            Image(systemName: "dumbbell")
                .resizable()
                .scaledToFit()
                .frame(width: controlIconSize, height: controlIconSize)
                .foregroundStyle(model.mode == .training ? Color.accentColor : Color.secondary)
                .modifier(CompactControlTarget(size: compactControlSize))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text("训练模式", "Training"))
        .accessibilityValue(model.mode == .training ? language.text("已开启", "On") : language.text("已关闭", "Off"))
        .accessibilityAddTraits(model.mode == .training ? .isSelected : [])
        .accessibilityHint(language.text("切换标准打乱与训练打乱", "Switch between standard and training scrambles"))
        .frame(minHeight: controlRowHeight)
    }
}

private struct CompactControlTarget: ViewModifier {
    let size: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    }
}

// The touch surface sits behind page controls and cancels an armed start on drag.
private struct TimerTouchSurface: UIViewRepresentable {
    var onDown: () -> Void
    var onUp: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> PressRecognizer { PressRecognizer() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.addGestureRecognizer(context.coordinator)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.callbacks = self
    }

    final class PressRecognizer: UIGestureRecognizer {
        var callbacks: TimerTouchSurface?
        private var initialPoint: CGPoint?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard initialPoint == nil, touches.count == 1, let touch = touches.first else {
                state = .failed
                return
            }
            initialPoint = touch.location(in: view)
            callbacks?.onDown()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let initialPoint, let point = touches.first?.location(in: view) else { return }
            if hypot(point.x - initialPoint.x, point.y - initialPoint.y) > 10 {
                state = .failed
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            guard initialPoint != nil else { return }
            initialPoint = nil
            state = .recognized
            callbacks?.onUp()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            state = .cancelled
        }

        override func reset() {
            if initialPoint != nil { callbacks?.onCancel() }
            initialPoint = nil
            super.reset()
        }
    }
}

private struct SVGView: UIViewRepresentable {
    let svg: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.ignoresViewportScaleLimits = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.pinchGestureRecognizer?.isEnabled = false
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.svg != svg else { return }
        context.coordinator.svg = svg
        let encodedSVG = Data(svg.utf8).base64EncodedString()
        view.loadHTMLString("""
            <!doctype html>
            <meta name="viewport" content="width=device-width,initial-scale=1,minimum-scale=1,maximum-scale=1,user-scalable=no">
            <style>
              html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; }
              img { display: block; width: 100%; height: 100%; object-fit: contain; object-position: right bottom; }
            </style>
            <img src="data:image/svg+xml;base64,\(encodedSVG)" alt="">
            """, baseURL: nil)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator {
        var svg = ""
    }
}
