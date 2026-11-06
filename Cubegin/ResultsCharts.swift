import Charts
import SwiftUI

struct ResultsCharts: View {
    let solves: [Solve]

    @Environment(\.locale) private var locale
    @State private var mode = Mode.trend
    @State private var range = AttemptRange.recent100
    @State private var hiddenAverages: Set<SolveAverage> = []
    @State private var plotColumns = 320
    @State private var rendered: (Request, ChartData)?
    @State private var cachedMeans: [SolveAverage: [Double?]] = [:]
    @State private var ordered: (source: [Solve], history: OrderedHistory)?
    private var language: AppLanguage { locale.appLanguage }

    private enum Mode: CaseIterable, Sendable {
        case trend, distribution

        var icon: String {
            switch self {
            case .trend: "chart.xyaxis.line"
            case .distribution: "chart.bar.xaxis"
            }
        }

        func title(_ language: AppLanguage) -> String {
            switch self {
            case .trend: language.text("趋势", "Trend")
            case .distribution: language.text("时间分布", "Time distribution")
            }
        }
    }

    private enum AttemptRange: Int, CaseIterable, Sendable {
        case recent5 = 5, recent12 = 12, recent50 = 50, recent100 = 100
        case recent500 = 500, recent1000 = 1000, recent10000 = 10000, all = 0

        func title(_ language: AppLanguage) -> String {
            self == .all ? language.text("全部", "All") : language.text("最近 \(rawValue) 次", "Last \(rawValue)")
        }
    }

    private struct Request: Equatable, Sendable {
        let solves: [Solve]
        let mode: Mode
        let range: AttemptRange
        let averages: [SolveAverage]
        let columns: Int
    }

    private enum ChartData: Sendable {
        case trend(TrendData)
        case distribution(DistributionData)
    }

    private var averages: [SolveAverage] {
        SolveAverage.allCases.filter { solves.count >= $0.count }
    }

    private var visibleAverages: [SolveAverage] {
        averages.filter { !hiddenAverages.contains($0) }
    }

    var body: some View {
        let rangeCounts = ordered?.source == solves ? ordered?.history.rangeCounts : nil
        let request = Request(solves: solves, mode: mode, range: range,
                              averages: mode == .trend ? visibleAverages : [],
                              columns: mode == .trend ? plotColumns : 0)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls(rangeCounts: rangeCounts)
                VStack(alignment: .leading, spacing: 16) {
                    Text(mode.title(language)).font(.headline)
                    if let rendered, rendered.0 == request {
                        switch rendered.1 {
                        case let .trend(data):
                            TrendChart(data: data)
                                .id(request.range)
                        case .distribution(let data):
                            distribution(data)
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 24))
                .onGeometryChange(for: Int.self) { geometry in
                    // Snap to width bands so resizing doesn't launch a task for each point.
                    max(128, min(768, Int(geometry.size.width - 60) / 32 * 32))
                } action: { plotColumns = $0 }
            }
            .frame(maxWidth: 832)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .task(id: request) {
            await load(request)
        }
    }

    private func controls(rangeCounts: [AttemptRange: Int]?) -> some View {
        let activeRange = rangeCounts?[range] == nil ? AttemptRange.all : range
        return HStack(spacing: 12) {
            Picker(language.text("图表类型", "Chart type"), selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { item in
                    Image(systemName: item.icon)
                        .accessibilityLabel(item.title(language))
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 96)
            .accessibilityIdentifier("charts.mode")

            Spacer(minLength: 0)

            Menu {
                Picker(language.text("范围", "Range"), selection: Binding(get: { activeRange }, set: { range = $0 })) {
                    ForEach(AttemptRange.allCases.filter { $0 == .all || rangeCounts?[$0] != nil }, id: \.self) { item in
                        Text(item.title(language)).tag(item)
                    }
                }
            } label: {
                menuLabel(activeRange.title(language))
            }
            .tint(.primary)
            .accessibilityIdentifier("charts.range")
            .disabled(rangeCounts == nil)

            if mode == .trend && !averages.isEmpty {
                let showsAllAverages = visibleAverages.count == averages.count
                let averagesTitle = language.text("平均线", "Averages")
                Menu {
                    Button(showsAllAverages
                           ? language.text("全部隐藏", "Hide all")
                           : language.text("全部显示", "Show all")) {
                        hiddenAverages = showsAllAverages ? Set(averages) : []
                    }
                    ForEach(averages, id: \.self) { kind in
                        Toggle(kind.title, isOn: Binding(
                            get: { !hiddenAverages.contains(kind) },
                            set: { isVisible in
                                if isVisible { hiddenAverages.remove(kind) }
                                else { hiddenAverages.insert(kind) }
                            }
                        ))
                    }
                } label: {
                    menuLabel(showsAllAverages ? language.text("全部", "All") : averagesTitle)
                }
                .tint(.primary)
                .accessibilityLabel(averagesTitle)
                .accessibilityValue(showsAllAverages ? language.text("全部", "All") : "")
                .accessibilityIdentifier("charts.average")
            }
        }
        .font(.subheadline.weight(.medium))
    }

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .foregroundStyle(.primary)
    }

    private func distribution(_ data: DistributionData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if data.bins.isEmpty {
                Text(language.text("暂无有效成绩", "No valid times"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(data.bins) { bin in
                    let label = bin.label(locale)
                    GridRow {
                        Text(label)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(bin.count == 0 ? .secondary : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                        GeometryReader { geometry in
                            if bin.count > 0 {
                                Capsule()
                                    .fill(Color.accentColor.opacity(bin.count == data.peak ? 0.9 : 0.34))
                                    .frame(width: geometry.size.width * CGFloat(bin.count) / CGFloat(data.peak))
                            }
                        }
                        .frame(height: 10)
                        Text(bin.count.formatted())
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(bin.count == 0 ? .secondary : .primary)
                            .gridColumnAlignment(.trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityValue(language.text("\(bin.count) 次", "\(bin.count) solves"))
                }
            }
        }
    }

    private func load(_ request: Request) async {
        let history: OrderedHistory
        if let ordered, ordered.source == request.solves {
            history = ordered.history
        } else {
            history = await Self.order(request.solves)
            guard !Task.isCancelled else { return }
            ordered = (request.solves, history)
            cachedMeans = [:]
        }

        let count = history.rangeCounts[request.range] ?? history.solves.count
        let missing = request.averages.filter { (cachedMeans[$0]?.count ?? 0) < count }
        if !missing.isEmpty {
            // Compute a recent window first. Expand to full history only on demand.
            let means = await Self.rollingMeans(history.solves, count: max(500, count), averages: missing)
            guard !Task.isCancelled else { return }
            for (kind, values) in means { cachedMeans[kind] = values }
        }
        let data = await Self.prepare(request, orderedSolves: history.solves, count: count, means: cachedMeans)
        guard !Task.isCancelled else { return }
        rendered = (request, data)
    }

    private struct OrderedHistory: Sendable {
        let solves: [Solve]
        // Each prefix reaches its target in valid solves and preserves intervening DNF slots.
        let rangeCounts: [AttemptRange: Int]
    }

    @concurrent private static func order(_ solves: [Solve]) async -> OrderedHistory {
        let sorted = solves.sorted(by: Solve.newestFirst)
        var rangeCounts: [AttemptRange: Int] = [.all: sorted.count]
        var ranges = AttemptRange.allCases.filter { $0 != .all }.makeIterator()
        var nextRange = ranges.next()
        var validCount = 0
        for (index, solve) in sorted.enumerated() where solve.resultSeconds != nil {
            validCount += 1
            if let range = nextRange, validCount == range.rawValue {
                rangeCounts[range] = index + 1
                nextRange = ranges.next()
                if nextRange == nil { break }
            }
        }
        return OrderedHistory(solves: sorted, rangeCounts: rangeCounts)
    }

    @concurrent private static func rollingMeans(_ solves: [Solve], count: Int, averages: [SolveAverage]) async -> [SolveAverage: [Double?]] {
        let visible = min(count, solves.count)
        let warmup = (averages.last?.count ?? 1) - 1
        let times = solves.prefix(visible + warmup).map(\.resultSeconds)
        var result: [SolveAverage: [Double?]] = [:]
        for kind in averages {
            guard !Task.isCancelled else { return [:] }
            var means = Array<Double?>(repeating: nil, count: visible)
            let windowInput = Array(times.prefix(visible + kind.count - 1))
            kind.forEachRollingMean(windowInput) { index, time in
                means[index] = time
            }
            result[kind] = means
        }
        return result
    }

    @concurrent private static func prepare(_ request: Request, orderedSolves: [Solve], count: Int, means: [SolveAverage: [Double?]]) async -> ChartData {
        let times = orderedSolves.prefix(count).reversed().map(\.resultSeconds)
        let sorted = times.compactMap { $0 }.sorted()
        switch request.mode {
        case .trend:
            let visible = request.averages.compactMap { kind in
                means[kind].map { (kind, Array($0.prefix(count).reversed())) }
            }
            return .trend(TrendData(times: times, means: visible, total: orderedSolves.count, sorted: sorted,
                                    columns: request.columns))
        case .distribution:
            return .distribution(DistributionData(sorted: sorted, typical: typicalRange(sorted)))
        }
    }
}

private struct TrendChart: View {
    let data: TrendData

    @Environment(\.locale) private var locale
    @State private var selection: Int?
    private var language: AppLanguage { locale.appLanguage }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            plot
                .frame(height: 290)
                .accessibilityLabel(language.text("成绩趋势", "Solve trend"))
            legend
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8, alignment: .leading)],
                      alignment: .leading, spacing: 10) {
                legendItem(language.text("单次", "Single"), color: singleColor)
                ForEach(data.averages, id: \.kind) { average in
                    legendItem(average.kind.title, color: averageColor(average.kind))
                }
            }
            if !data.bands.isEmpty && !data.averages.isEmpty {
                Text(language.text("曲线按段汇总", "Lines aggregated"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("charts.legend")
    }

    private let singleColor = Color.gray.opacity(0.62)

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 11, height: 3)
                .accessibilityHidden(true)
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.caption.weight(.medium))
    }

    private func averageColor(_ kind: SolveAverage) -> Color {
        switch kind {
        case .mo3: .teal
        case .ao5: .orange
        case .ao12: .blue
        case .ao50: .purple
        case .ao100: .green
        case .ao500: .pink
        case .ao1000: .indigo
        case .ao10000: .brown
        }
    }

    private var plot: some View {
        Chart {
            RectanglePlot(data.bands, xStart: .value("", \.start), xEnd: .value("", \.end),
                          yStart: .value("", \.low), yEnd: .value("", \.high))
                .foregroundStyle(Color.gray.opacity(0.25))
            series(data.singles, name: language.text("单次", "Single"), color: singleColor, width: 1)
            ForEach(data.averages, id: \.kind) { average in
                series(average.series, name: average.kind.title, color: averageColor(average.kind), width: 1.5)
            }
            if let selection, (data.first...data.last).contains(selection) {
                RuleMark(x: .value(language.text("序号", "Attempt"), Double(selection)))
                    .foregroundStyle(.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXSelection(value: Binding<Double?>(
            get: { selection.map(Double.init) },
            set: { value in
                if let value { selection = Int(value.rounded()) }
            }
        ))
        .chartXScale(domain: Double(data.first) - 0.5...Double(data.last) + 0.5)
        .chartYScale(domain: data.scale.domain)
        .chartXAxis {
            AxisMarks(values: data.attemptTicks.map(Double.init)) { value in
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(Int(number).formatted()).font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: data.scale.tickPositions) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.25))
                AxisValueLabel {
                    if let position = value.as(Double.self), let seconds = data.scale.tickTimes[position] {
                        Text(chartTime(seconds, locale: locale)).font(.caption2.monospacedDigit())
                    }
                }
            }
        }
    }

    @ChartContentBuilder
    private func series(_ series: TrendData.Series, name: String, color: Color, width: CGFloat) -> some ChartContent {
        let x = PlottableProjection<TrendData.Point, Double>.value(language.text("序号", "Attempt"), \.attempt)
        let y = PlottableProjection<TrendData.Point, Double>.value(name, \.time)
        LinePlot(series.lines, x: x, y: y, series: .value("", \.segment))
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        PointPlot(series.dots, x: x, y: y)
            .foregroundStyle(color)
            .symbolSize(12)
    }
}

private struct TrendData: Sendable {
    struct Point: Sendable {
        let attempt: Double
        let time: Double
        let segment: Int
    }

    struct Band: Sendable {
        let start: Double
        let end: Double
        let low: Double
        let high: Double
    }

    struct Series: Sendable {
        var lines: [Point] = []
        var dots: [Point] = []

        init() {}

        init(_ times: [Double?], first: Int, scale: TrendScale, stride: Int, slot: Int = 0) {
            var run: [Point] = []
            // Swift Charts groups lines by series across plots. Reserve separate IDs.
            var segment = slot

            let slots = SolveAverage.allCases.count + 1

            func finishRun() {
                if run.count == 1 { dots.append(run[0]) }
                else { lines.append(contentsOf: run) }
                run.removeAll(keepingCapacity: true)
                segment += slots
            }

            for start in Swift.stride(from: 0, to: times.count, by: stride) {
                if Task.isCancelled { return }
                let end = min(start + stride, times.count)
                var lower = Bucket()
                var upper = Bucket()
                for index in start..<end {
                    guard let time = times[index] else { continue }
                    if scale.isAboveGap(time) { upper.add(time, attempt: first + index) }
                    else { lower.add(time, attempt: first + index) }
                }
                let crossesGap = lower.count > 0 && upper.count > 0
                let continuous = lower.count + upper.count == end - start && !crossesGap
                if !continuous { finishRun() }
                for bucket in [lower, upper] where bucket.count > 0 {
                    // Keep the average of a dense bucket on its side of the empty interval.
                    let point = Point(attempt: bucket.attemptSum / Double(bucket.count),
                                      time: scale.position(bucket.timeSum / Double(bucket.count)), segment: segment)
                    if continuous { run.append(point) }
                    else { dots.append(point) }
                }
            }
            finishRun()
        }
    }

    private struct Bucket {
        var count = 0
        var timeSum = 0.0
        var attemptSum = 0.0

        mutating func add(_ time: Double, attempt: Int) {
            count += 1
            timeSum += time
            attemptSum += Double(attempt)
        }
    }

    struct Average: Sendable {
        let kind: SolveAverage
        let series: Series
    }

    let first: Int
    let last: Int
    let attemptTicks: [Int]
    let scale: TrendScale
    let singles: Series
    let averages: [Average]
    let bands: [Band]

    init(times: [Double?], means: [(SolveAverage, [Double?])], total: Int, sorted: [Double], columns: Int) {
        let first = total - times.count + 1
        self.first = first
        last = total

        let attemptStep = max(1, Int(niceStep(Double(max(1, times.count - 1)) / 5)))
        let firstTick = ((first + attemptStep - 1) / attemptStep) * attemptStep
        attemptTicks = Array(stride(from: firstTick, through: total, by: attemptStep))

        let scale = TrendScale(singles: sorted, means: means.map { $0.1 })
        self.scale = scale

        let dense = times.count > max(500, columns)
        let bucketSize = dense ? (times.count + columns - 1) / columns : 1
        averages = means.enumerated().map { slot, entry in
            let (kind, values) = entry
            return Average(kind: kind,
                           series: Series(values, first: first, scale: scale, stride: bucketSize, slot: slot + 1))
        }
        singles = dense ? Series() : Series(times, first: first, scale: scale, stride: 1)
        bands = dense ? stride(from: 0, to: times.count, by: bucketSize).flatMap { start -> [Band] in
            guard !Task.isCancelled else { return [] }
            let end = min(start + bucketSize, times.count)
            var lower = BandBounds()
            var upper = BandBounds()
            for case let time? in times[start..<end] {
                if scale.isAboveGap(time) { upper.add(scale.position(time)) }
                else { lower.add(scale.position(time)) }
            }
            let halfStroke = (scale.domain.upperBound - scale.domain.lowerBound) / 400
            return [lower, upper].compactMap { bounds in
                guard bounds.minimum <= bounds.maximum else { return nil }
                return Band(start: Double(first + start) - 0.5, end: Double(first + end) - 0.5,
                            low: max(scale.domain.lowerBound, bounds.minimum - halfStroke),
                            high: min(scale.domain.upperBound, bounds.maximum + halfStroke))
            }
        } : []
    }
}

private struct BandBounds {
    var minimum = Double.infinity
    var maximum = -Double.infinity

    mutating func add(_ value: Double) {
        minimum = min(minimum, value)
        maximum = max(maximum, value)
    }
}

private struct TrendScale: Sendable {
    let domain: ClosedRange<Double>
    let tickPositions: [Double]
    let tickTimes: [Double: Double]
    private let gap: Gap?

    private struct Gap: Sendable {
        let lower: Double
        let upper: Double
        let displayed: Double

        func position(_ time: Double) -> Double {
            let offset = min(max(time - lower, 0), upper - lower)
            return time - offset * (1 - displayed / (upper - lower))
        }
    }

    init(singles: [Double], means: [[Double?]]) {
        let low = singles.first ?? 0
        let high = singles.last ?? 1
        var minimum = low
        var maximum = high
        for values in means {
            for case let value? in values {
                minimum = min(minimum, value)
                maximum = max(maximum, value)
            }
        }
        let gap = Self.emptyGap(singles: singles, means: means, minimum: minimum, maximum: maximum)
        self.gap = gap
        let upper = gap?.position(maximum) ?? maximum
        let buffer = max(0.10, (upper - minimum) * 0.07, upper * 0.0125)
        let domain = max(0, minimum - buffer)...(upper + buffer)
        self.domain = domain
        let step = niceStep((domain.upperBound - domain.lowerBound) / 5)
        let ranges = gap.map {
            [domain.lowerBound...$0.lower, $0.upper...(maximum + buffer)]
        } ?? [domain]
        let ticks = ranges.enumerated().flatMap { index, range -> [Double] in
            let start = Int(ceil(range.lowerBound / step))
            let end = Int(floor(range.upperBound / step))
            if start <= end { return (start...end).map { Double($0) * step } }
            return [index == 0 ? minimum : maximum]
        }
        tickPositions = ticks.map { gap?.position($0) ?? $0 }
        tickTimes = Dictionary(uniqueKeysWithValues: zip(tickPositions, ticks))
    }

    func position(_ time: Double) -> Double { gap?.position(time) ?? time }

    func isAboveGap(_ time: Double) -> Bool {
        guard let gap else { return false }
        return time >= gap.upper
    }

    private static func emptyGap(singles: [Double], means: [[Double?]], minimum: Double, maximum: Double) -> Gap? {
        guard !singles.isEmpty else { return nil }
        // Find a candidate from single times, then check for average values inside it.
        var candidate = minimum...minimum
        var previous = minimum
        for time in singles {
            if time - previous > candidate.upperBound - candidate.lowerBound {
                candidate = previous...time
            }
            previous = time
        }
        if maximum - previous > candidate.upperBound - candidate.lowerBound { candidate = previous...maximum }
        let span = maximum - minimum
        let threshold = max(1, minimum * 0.2, span * 0.42)
        guard candidate.upperBound - candidate.lowerBound >= threshold else { return nil }

        var interior: [Double] = []
        for values in means {
            for case let value? in values where value > candidate.lowerBound && value < candidate.upperBound {
                interior.append(value)
            }
        }
        previous = candidate.lowerBound
        var largest = previous...previous
        interior.sort()
        interior.append(candidate.upperBound)
        for value in interior {
            if value - previous > largest.upperBound - largest.lowerBound { largest = previous...value }
            previous = value
        }
        let width = largest.upperBound - largest.lowerBound
        guard width >= threshold else { return nil }
        return Gap(lower: largest.lowerBound, upper: largest.upperBound, displayed: max(0.25, (span - width) * 0.25))
    }
}

private struct DistributionData: Sendable {
    struct Bin: Identifiable, Sendable {
        let id: Int
        let lower: Double?
        let upper: Double?
        let count: Int

        func label(_ locale: Locale) -> String {
            switch (lower, upper) {
            case let (lower?, upper?): "\(chartTime(lower, locale: locale))–\(chartTime(upper, locale: locale))"
            case let (nil, upper?): "< \(chartTime(upper, locale: locale))"
            case let (lower?, nil): "≥ \(chartTime(lower, locale: locale))"
            case (nil, nil): "—"
            }
        }
    }

    let bins: [Bin]
    let peak: Int

    init(sorted: [Double], typical: ClosedRange<Double>?) {
        guard let typical else {
            bins = []
            peak = 1
            return
        }

        let step = niceStep(max(0.1, (typical.upperBound - typical.lowerBound) / 9))
        func binIndex(_ time: Double) -> Int {
            Int(floor(time / step + 1e-9))
        }
        let lower = binIndex(typical.lowerBound)
        let upper = binIndex(typical.upperBound)
        var counts = Array(repeating: 0, count: upper - lower + 3)
        for time in sorted {
            let index = binIndex(time) - lower + 1
            counts[min(counts.count - 1, max(0, index))] += 1
        }
        guard let first = counts.firstIndex(where: { $0 > 0 }),
              let last = counts.lastIndex(where: { $0 > 0 }) else {
            bins = []
            peak = 1
            return
        }

        var rows: [Bin] = []
        var index = first
        while index <= last {
            let count = counts[index]
            var end = index
            if count == 0 {
                while end < last && counts[end + 1] == 0 { end += 1 }
            }
            rows.append(Bin(
                id: index,
                lower: index == 0 ? nil : Double(lower + index - 1) * step,
                upper: end == counts.count - 1 ? nil : Double(lower + end) * step,
                count: count
            ))
            index = end + 1
        }
        bins = rows
        peak = counts.max() ?? 1
    }
}

private func typicalRange(_ sorted: [Double]) -> ClosedRange<Double>? {
    guard let low = sorted.first, let high = sorted.last else { return nil }
    guard sorted.count >= 20 else { return low...high }
    let q1 = sorted[(sorted.count - 1) / 4]
    let q3 = sorted[(sorted.count - 1) * 3 / 4]
    let margin = max(0.25, 3 * (q3 - q1))
    var first = 0
    var last = sorted.count - 1
    while sorted[first] < q1 - margin { first += 1 }
    while sorted[last] > q3 + margin { last -= 1 }
    let excluded = first + sorted.count - 1 - last
    guard excluded <= sorted.count / 20 else { return low...high }
    return sorted[first]...sorted[last]
}

private func niceStep(_ ideal: Double) -> Double {
    let magnitude = pow(10, floor(log10(ideal)))
    return ([1.0, 2, 2.5, 5, 10].first { $0 >= ideal / magnitude } ?? 10) * magnitude
}

private func chartTime(_ seconds: Double, locale: Locale) -> String {
    if seconds < 60 {
        return seconds.formatted(.number.precision(.fractionLength(0...3)).locale(locale))
            + "s"
    }
    let milliseconds = Int((seconds * 1_000).rounded())
    let whole = milliseconds / 1_000
    let minutes = whole / 60
    let clock = minutes < 60
        ? String(format: "%02d:%02d", minutes, whole % 60)
        : String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, whole % 60)
    let fraction = milliseconds % 1_000
    guard fraction > 0 else { return clock }
    let decimal = (Double(fraction) / 1_000).formatted(.number.precision(.fractionLength(0...3)).locale(locale))
    return clock + decimal.dropFirst()
}
