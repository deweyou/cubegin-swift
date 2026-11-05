import SwiftUI
import UIKit

struct AppTabsView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }

    var isActive: Bool
    @State private var model = TimerModel()
    @State private var selection = Destination.home
    @Environment(\.scenePhase) private var scenePhase

    private enum Destination { case home, results, settings }

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: Destination.home) {
                ContentView(model: model, isTimerActive: isActive && selection == .home && scenePhase == .active)
                    .labelStyle(.titleAndIcon)
                    .toolbar(model.started == nil ? .automatic : .hidden, for: .tabBar)
            } label: {
                Label(language.text("首页", "Home"), image: "NavigationHome")
            }
            Tab(value: Destination.results) {
                ResultsView(model: model)
                    .labelStyle(.titleAndIcon)
            } label: {
                Label {
                    Text(language.text("成绩", "Results"))
                } icon: {
                    Image(uiImage: NavigationIcons.results)
                }
            }
            Tab(value: Destination.settings) {
                SettingsView()
                    .labelStyle(.titleAndIcon)
            } label: {
                Label {
                    Text(language.text("设置", "Settings"))
                } icon: {
                    Image(uiImage: NavigationIcons.settings)
                }
            }
        }
        .labelStyle(.iconOnly)
        .task(id: isActive ? model.event : nil) {
            guard isActive else { return }
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.interrupt() }
        }
        .alert(language.text("提示", "Notice"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(language.text("好", "OK")) { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

}

// Fixed-size image assets keep the native tab bar from overriding symbol point sizes.
@MainActor private enum NavigationIcons {
    static let results = icon("list.bullet")
    static let settings = icon("gearshape")

    private static func icon(_ name: String) -> UIImage {
        let side: CGFloat = 28
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return UIImage() }
        let scale = min(side / symbol.size.width, side / symbol.size.height)
        let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            symbol.withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: CGRect(
                x: (side - size.width) / 2, y: (side - size.height) / 2,
                width: size.width, height: size.height
            ))
        }.withRenderingMode(.alwaysTemplate)
    }
}

private struct ResultsView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }

    let model: TimerModel

    var body: some View {
        NavigationStack {
            Group {
                if model.solves.isEmpty {
                    ContentUnavailableView(language.text("还没有成绩", "No results yet"), systemImage: "stopwatch", description: Text(language.text("在首页完成一次计时，成绩会保存在这里。", "Time a solve on the Home tab to see it here.")))
                } else {
                    List(model.solves) { solve in
                        NavigationLink {
                            Form {
                                Section {
                                    LabeledContent(language.text("成绩", "Time"), value: solve.resultText)
                                    if solve.penalty != nil {
                                        LabeledContent(language.text("原始计时", "Original time"), value: TimerModel.format(solve.seconds))
                                    }
                                    LabeledContent(language.text("项目", "Event"), value: eventName(solve.event))
                                    LabeledContent(language.text("日期", "Date"), value: solve.date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().second().locale(locale)))
                                }
                                Section(language.text("打乱", "Scramble")) {
                                    Text(solve.scramble).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                }
                            }
                            .navigationTitle(language.text("成绩详情", "Solve details"))
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(solve.resultText).font(.title3.monospacedDigit().weight(.medium))
                                    Text(solve.date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(locale))).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(eventName(solve.event)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle(language.text("成绩", "Results"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func eventName(_ event: String) -> String {
        ScrambleCatalog.title(event, in: language)
    }
}

private struct SettingsView: View {
    @AppStorage(AppLanguage.preferenceKey) private var selectedLanguage = AppLanguage.chinese
    @AppStorage(TimerModel.startDelayKey) private var startDelayTenths = TimerModel.defaultStartDelayTenths
    @Environment(\.locale) private var locale
    private var language: AppLanguage { locale.appLanguage }

    var body: some View {
        NavigationStack {
            Form {
                Picker(language.text("语言", "Language"), selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.name).tag(option)
                    }
                }
                Section(language.text("计时", "Timer")) {
                    Stepper(value: $startDelayTenths, in: 0...20) {
                        LabeledContent(language.text("启动延迟", "Start delay"),
                                       value: (Double(startDelayTenths) / 10).formatted(.number.precision(.fractionLength(1))) + " s")
                    }
                }
                Section(language.text("外观", "Appearance")) {
                    LabeledContent(language.text("主题", "Theme"), value: language.text("跟随系统", "System"))
                }
                Section(language.text("关于", "About")) {
                    LabeledContent(language.text("应用", "App"), value: "cubegin")
                    LabeledContent(language.text("版本", "Version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? language.text("开发版", "Development build"))
                }
            }
            .navigationTitle(language.text("设置", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
