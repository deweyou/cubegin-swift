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
    @State private var timerTouchResumesAt: ContinuousClock.Instant?
    @State private var solveToDelete: Solve?
    @State private var showsGenerating = false
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
            model.cancelPress()
            if !isShowing {
                // The tap dismissing the popover can also reach the page beneath it.
                timerTouchResumesAt = .now.advanced(by: .milliseconds(250))
                if isTimerActive { hasTimerKeyboardFocus = true }
            }
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
        .task(id: model.busy) {
            showsGenerating = false
            guard model.busy else { return }
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            if model.busy { showsGenerating = true }
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
        let timerTouchTop = isTiming ? 0 : topClearance + controlsHeight + controlSpacing
        let formulaHeight = max(1, min(height * 0.3,
            height / 2 - timerNumberHeight / 2 - controlsHeight - controlSpacing - topClearance - 8))
        let footerSpacing: CGFloat = 12
        let footerWidth = max(0, contentWidth - footerSpacing)
        let summaryWidth = min(144, footerWidth * 0.46)
        let diagramWidth = footerWidth - summaryWidth
        let diagramClearance: CGFloat = model.lastSolve == nil ? 68 : max(68, 14 + compactControlSize + diagramBottomPadding + 8)
        let diagramHeight = max(0, min(180, height / 2 - timerNumberHeight / 2 - diagramClearance))

        let diagramAspectRatio = model.scramble?.diagramAspectRatio ?? (4.0 / 3)
        let summaryHeight = min(diagramHeight, diagramWidth / CGFloat(diagramAspectRatio))

        return ZStack {
            TimerTouchSurface(
                onDown: {
                    guard isTimerActive, !showsProjectList, solveToDelete == nil else { return }
                    if let timerTouchResumesAt, ContinuousClock.now < timerTouchResumesAt { return }
                    model.press(.touch, delayTenths: startDelayTenths)
                },
                onUp: { model.release(.touch) },
                onCancel: { model.cancelPress(.touch) }
            )
            .frame(width: width, height: max(0, height - timerTouchTop))
            .frame(width: contentWidth, height: height, alignment: .bottom)
            .allowsHitTesting(isTimerActive && !showsProjectList && solveToDelete == nil)
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
                        if model.busy {
                            if showsGenerating {
                                Text(language.text("生成中…", "Generating…"))
                                    .foregroundStyle(.secondary)
                            }
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

            HStack(alignment: .bottom, spacing: footerSpacing) {
                if !isTiming && summaryHeight > 0 {
                    TimerSummary(model: model, height: summaryHeight)
                        .frame(width: summaryWidth)
                }
                SVGView(svg: model.scramble?.svg, nextSVG: model.nextScramble?.svg)
                    .frame(width: diagramWidth, height: diagramHeight)
                    .accessibilityLabel(language.text("当前打乱状态图", "Current scramble diagram"))
                    .accessibilityIdentifier("timer.scramble-diagram")
            }
            .padding(.bottom, diagramBottomPadding)
            .frame(height: height, alignment: .bottom)
            .opacity(isTiming || diagramHeight == 0 ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(isTiming || diagramHeight == 0)

            timerDisplay(fontSize: timerFontSize, numberHeight: timerNumberHeight)
                .frame(width: max(1, min(timerFrame.width, 880) - 48))
                .offset(x: timerFrame.midX - frame.midX, y: timerFrame.midY - frame.midY)
        }
        .frame(height: height)
        .padding(.horizontal, 24)
        .frame(maxWidth: 880)
        .frame(maxWidth: .infinity)
        .appBackground()
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
        EventPicker(model: model, isPresented: $showsProjectList, large: usesTopNavigation)
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
                 "compactPicker": width(EventPicker.projectButton(event: choice.id, language: language, large: false, action: {}), language: language),
                 "regularPicker": width(EventPicker.projectButton(event: choice.id, language: language, large: true, action: {}), language: language)] as [String: Any]
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

    private var trainingButton: some View { TrainingButton(model: model) }

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

private struct TimerSummary: View {
    let model: TimerModel
    let height: CGFloat
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .footnote) private var preferredFontSize: CGFloat = 13

    private static let averageKinds: [SolveAverage] = [.mo3, .ao5, .ao12]

    var body: some View {
        let solves = model.groupSolves
        let language = locale.appLanguage
        let latestCount = SolveAverage.ao12.count
        var validCount = 0
        var total = 0.0
        var best: Solve?
        var recent: [Solve] = []

        for solve in solves {
            if let seconds = solve.resultSeconds {
                validCount += 1
                total += seconds
                if let fastest = best, let fastestSeconds = fastest.resultSeconds {
                    if seconds < fastestSeconds || (seconds == fastestSeconds && Solve.newestFirst(solve, fastest)) {
                        best = solve
                    }
                } else {
                    best = solve
                }
            }

            if recent.count < latestCount || Solve.newestFirst(solve, recent[latestCount - 1]) {
                let index = recent.firstIndex { Solve.newestFirst(solve, $0) } ?? recent.endIndex
                recent.insert(solve, at: index)
                if recent.count > latestCount { recent.removeLast() }
            }
        }

        let rowHeight = min(20, height / 6)
        let fontSize = min(preferredFontSize, rowHeight * 0.76)
        let mean = validCount > 0 ? TimerModel.format(total / Double(validCount)) : "—"

        return VStack(spacing: 0) {
            row(nil, value: "\(validCount.formatted()) / \(solves.count.formatted())",
                accessibilityName: language.text("有效成绩次数 / 总次数", "Valid solves / Total attempts"),
                id: "count", fontSize: fontSize, height: rowHeight)
            row("mean", value: mean, accessibilityName: language.text("总平均", "Overall mean"),
                id: "mean", fontSize: fontSize, height: rowHeight)
            row("best", value: best?.resultText ?? "—", accessibilityName: language.text("最好单次", "Best single"),
                id: "best", fontSize: fontSize, height: rowHeight)
            ForEach(Self.averageKinds, id: \.self) { kind in
                let value = recent.count >= kind.count
                    ? kind.summarize(recent.prefix(kind.count)).mean.map(TimerModel.format) ?? "DNF"
                    : "—"
                row(kind.title, value: value, accessibilityName: kind.title,
                    id: kind.title, fontSize: fontSize, height: rowHeight)
            }
        }
    }

    private func row(_ title: String?, value: String, accessibilityName: String,
                     id: String, fontSize: CGFloat, height: CGFloat) -> some View {
        let text = if let title {
            Text("\(Text("\(title):").foregroundColor(.secondary)) \(value)")
        } else {
            Text(value)
        }
        return text
            .font(.system(size: fontSize, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityName)
            .accessibilityValue(value)
            .accessibilityIdentifier("timer-summary.\(id)")
    }
}

struct SVGView: UIViewRepresentable {
    let svg: String?
    let nextSVG: String?
    var centersContent = false

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.setCentersContent(centersContent)
        context.coordinator.update(in: view, svg: svg, nextSVG: nextSVG)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // Keep the visible diagram intact while the other WebView loads its replacement.
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var centersContent = false

        func setCentersContent(_ value: Bool) {
            guard centersContent != value else { return }
            centersContent = value
            slots.forEach { $0.svg = nil }
        }
        @MainActor private final class Slot {
            let view: WKWebView
            var svg: String?
            var navigation: WKNavigation?
            var ready = false

            init() {
                let configuration = WKWebViewConfiguration()
                configuration.defaultWebpagePreferences.allowsContentJavaScript = false
                configuration.ignoresViewportScaleLimits = false
                view = WKWebView(frame: .zero, configuration: configuration)
                view.isOpaque = false
                view.backgroundColor = .clear
                view.scrollView.isScrollEnabled = false
                view.scrollView.pinchGestureRecognizer?.isEnabled = false
                view.isHidden = true
            }
        }

        private var slots: [Slot] = []
        private var visible: Slot?
        private var desiredSVG: String?

        func update(in container: UIView, svg: String?, nextSVG: String?) {
            desiredSVG = svg
            if let svg, visible?.svg != svg {
                if let loaded = slots.first(where: { $0.svg == svg && $0.ready }) {
                    show(loaded)
                } else {
                    load(svg, in: container)
                    return
                }
            }
            if let nextSVG, nextSVG != visible?.svg {
                load(nextSVG, in: container)
            }
        }

        private func load(_ svg: String, in container: UIView) {
            let slot: Slot
            if let spare = slots.first(where: { $0 !== visible }) {
                slot = spare
            } else {
                slot = Slot()
                slots.append(slot)
                slot.view.navigationDelegate = self
                slot.view.frame = container.bounds
                slot.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.addSubview(slot.view)
            }
            guard slot.svg != svg else { return }
            slot.svg = svg
            slot.ready = false
            let encodedSVG = Data(svg.utf8).base64EncodedString()
            slot.navigation = slot.view.loadHTMLString("""
                <!doctype html>
                <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
                <style>
                  html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; }
                  img { display: block; width: 100%; height: 100%; object-fit: contain; object-position: \(centersContent ? "center" : "right bottom"); }
                </style>
                <img src="data:image/svg+xml;base64,\(encodedSVG)" alt="">
                """, baseURL: nil)
        }

        private func show(_ slot: Slot) {
            visible?.view.isHidden = true
            slot.view.isHidden = false
            visible = slot
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let slot = slots.first(where: { $0.view === webView }),
                  slot.navigation === navigation else { return }
            slot.ready = true
            if let desiredSVG, slot.svg == desiredSVG { show(slot) }
        }
    }
}

struct EventPicker: View {
    @Bindable var model: TimerModel
    @Binding var isPresented: Bool
    var large = false
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }
    private var showsProjectList: Bool {
        get { isPresented }
        nonmutating set { isPresented = newValue }
    }
    var body: some View {
        Self.projectButton(event: model.event, language: language, large: large) {
            showsProjectList = true
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
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

    static func projectButton(event: String, language: AppLanguage, large: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            projectMenuLabel(event: event, language: language, large: large)
        }
        .buttonStyle(.plain)
        .controlSize(large ? .regular : .small)
        .accessibilityLabel(language.text("打乱项目", "Event"))
        .accessibilityValue(ScrambleCatalog.title(event, in: language))
    }

    static func projectMenuLabel(event: String, language: AppLanguage, large: Bool) -> some View {
        let iconID = String(event.prefix { $0 != "." })
        return HStack(spacing: 6) {
            Image("Event-\(iconID)")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
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
        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

}

struct TrainingButton: View {
    @Bindable var model: TimerModel
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }
    var body: some View {
        Button {
            model.mode = model.mode == .training ? .standard : .training
        } label: {
            Image(systemName: "dumbbell")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(model.mode == .training ? Color.accentColor : Color.secondary)
                .modifier(CompactControlTarget(size: 32))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text("训练模式", "Training"))
        .accessibilityValue(model.mode == .training ? language.text("已开启", "On") : language.text("已关闭", "Off"))
        .accessibilityAddTraits(model.mode == .training ? .isSelected : [])
        .accessibilityHint(language.text("切换标准打乱与训练打乱", "Switch between standard and training scrambles"))
        .frame(minHeight: 44)
    }
}

private struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.cyan.opacity(0.14), Color(.systemBackground), Color.indigo.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

extension View {
    func appBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { AppBackground() }
    }
}
