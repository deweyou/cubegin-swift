import SwiftUI

struct Solve: Codable, Identifiable {
    var id = UUID()
    let seconds: Double
    let event: String
    let scramble: String
    var date = Date()
}
@MainActor @Observable final class TimerModel {
    var event = "333"
    var scramble: Scramble?
    var busy = false
    var error: String?
    var assistance: String?
    var started: ContinuousClock.Instant?
    var elapsed = 0.0
    var solves: [Solve] = []
    private let storage = URL.documentsDirectory.appending(path: "solves.json")
    init() {
        do { solves = try JSONDecoder().decode([Solve].self, from: Data(contentsOf: storage)) }
        catch { if FileManager.default.fileExists(atPath: storage.path) { self.error = "成绩读取失败：\(error.localizedDescription)" } }
    }
    var session: [Solve] { solves.filter { $0.event == event } }
    func refresh() async {
        guard !busy, started == nil else { return }
        busy = true; scramble = nil; assistance = nil
        defer { busy = false }
        do { scramble = try await Engine.scramble(event: event) } catch { self.error = error.localizedDescription }
    }
    func toggle() {
        if let start = started {
            let duration = start.duration(to: .now)
            elapsed = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            started = nil
            solves.insert(Solve(seconds: elapsed, event: event, scramble: scramble?.algorithm ?? ""), at: 0)
            do { try JSONEncoder().encode(solves).write(to: storage, options: .atomic) } catch { self.error = "成绩保存失败：\(error.localizedDescription)" }
            Task { await refresh() }
        } else if scramble != nil, !busy { started = .now }
    }
    func assist() async {
        guard let scramble, !busy, started == nil else { return }
        busy = true
        defer { busy = false }
        do { assistance = try await Engine.cross(algorithm: scramble.algorithm) } catch { self.error = error.localizedDescription }
    }
    static func format(_ time: Double) -> String { String(format: "%.2f", time) }
}
