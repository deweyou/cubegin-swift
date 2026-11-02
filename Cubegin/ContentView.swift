import SwiftUI
import WebKit

struct ContentView: View {
    @State private var model = TimerModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 28) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("CUBEGIN").font(.caption.weight(.bold)).tracking(4)
                                Text("专注每一次转动").font(.title2.weight(.semibold))
                            }
                            Spacer()
                            Picker("项目", selection: $model.event) {
                                Text("2 × 2").tag("222")
                                Text("3 × 3").tag("333")
                                Text("4 × 4").tag("444")
                                Text("金字塔").tag("pyram")
                            }.disabled(model.busy || model.started != nil).pickerStyle(.menu)
                        }
                        VStack(spacing: 18) {
                            HStack {
                                Label("随机打乱", systemImage: "shuffle").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                                    .disabled(model.busy || model.started != nil).accessibilityLabel("重新生成打乱")
                            }
                            if model.busy { ProgressView("计算中…") }
                            Text(model.scramble?.algorithm ?? "准备你的下一次挑战")
                                .font(.system(.title3, design: .monospaced)).lineSpacing(7).frame(maxWidth: .infinity)
                                .textSelection(.enabled)
                        }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                        Button { model.toggle() } label: {
                            VStack(spacing: 14) {
                                TimelineView(.animation(minimumInterval: 0.03, paused: model.started == nil)) { _ in
                                    let duration = model.started.map { $0.duration(to: .now) }
                                    let seconds = duration.map { Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18 } ?? model.elapsed
                                    Text(TimerModel.format(seconds)).font(.system(size: geometry.size.width > 600 ? 110 : 76, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                                }
                                Text(model.started == nil ? "轻触开始计时" : "轻触停止").font(.subheadline).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 30).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(model.scramble == nil && model.started == nil)
                            .accessibilityLabel(model.started == nil ? "开始计时" : "停止计时")
                        HStack(spacing: 16) {
                            statistic("完成", "\(model.session.count)")
                            statistic("最佳", model.session.map(\.seconds).min().map(TimerModel.format) ?? "—")
                            statistic("平均", model.session.isEmpty ? "—" : TimerModel.format(model.session.map(\.seconds).reduce(0, +) / Double(model.session.count)))
                        }
                        if let svg = model.scramble?.svg {
                            SVGView(svg: svg).frame(height: 180).accessibilityLabel("当前打乱状态图")
                        }
                        if model.event == "333" {
                            Button { Task { await model.assist() } } label: { Label("查看 Cross 辅助", systemImage: "sparkles") }
                                .buttonStyle(.glass).disabled(model.busy || model.started != nil || model.scramble == nil)
                        }
                        if let assistance = model.assistance { Text(assistance).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                        if !model.session.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("最近成绩").font(.headline)
                                ForEach(model.session.prefix(20)) { solve in
                                    HStack {
                                        Text(solve.date, style: .time).foregroundStyle(.secondary)
                                        Spacer()
                                        Text(TimerModel.format(solve.seconds)).monospacedDigit().fontWeight(.medium)
                                    }
                                }
                            }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                        }
                    }.padding(24).frame(maxWidth: 880).frame(maxWidth: .infinity)
                }
            }
            .background {
                LinearGradient(colors: [Color.cyan.opacity(0.14), Color(.systemBackground), Color.indigo.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            }
            .toolbar { ToolbarItem(placement: .principal) { Label("cubegin", systemImage: "cube.transparent").font(.headline) } }
            .task(id: model.event) { await model.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active, model.started != nil { model.started = nil; model.error = "计时因 App 进入后台或中断而取消，未保存成绩。" }
            }
            .alert("提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("好") { model.error = nil } } message: { Text(model.error ?? "") }
        }
    }
    private func statistic(_ title: String, _ value: String) -> some View {
        VStack(spacing: 8) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.monospacedDigit()) }
            .frame(maxWidth: .infinity).padding(.vertical, 18).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct SVGView: UIViewRepresentable {
    let svg: String
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false; view.backgroundColor = .clear; view.scrollView.isScrollEnabled = false
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.svg != svg else { return }
        context.coordinator.svg = svg
        view.loadHTMLString("<meta name='viewport' content='width=device-width,initial-scale=1'><style>body{margin:0;display:grid;place-items:center;height:100vh;background:transparent}svg{max-width:100%;max-height:100vh}</style>" + svg, baseURL: nil)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator { var svg = "" }
}
