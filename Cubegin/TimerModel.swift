import SwiftUI

enum SolvePenalty: String, Codable, Sendable { case plusTwo, dnf }

struct Solve: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let seconds: Double
    let event: String
    let scramble: String
    var date = Date()
    var penalty: SolvePenalty?
    var groupID: String?

    var resultSeconds: Double? {
        switch penalty {
        case .plusTwo: seconds + 2
        case .dnf: nil
        case nil: seconds
        }
    }

    static func newestFirst(_ lhs: Solve, _ rhs: Solve) -> Bool {
        lhs.date == rhs.date ? lhs.id.uuidString < rhs.id.uuidString : lhs.date > rhs.date
    }

    @MainActor var resultText: String {
        switch penalty {
        case .plusTwo: TimerModel.format(seconds + 2) + "+"
        case .dnf: "DNF"
        case nil: TimerModel.format(seconds)
        }
    }
}
struct SolveGroup: Codable, Identifiable {
    static let maximumNameLength = 16

    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maximumNameLength && trimmed.rangeOfCharacter(from: .newlines) == nil
    }

    var id: String
    let event: String
    var name: String
    var isDefault: Bool
    var displayName: String { name.isEmpty ? "Default" : name }

    static func initialID(for event: String) -> String { "default:" + event }
}

private struct ResultsStore: Codable {
    var solves: [Solve]
    var groups: [SolveGroup]
}

enum TimerInput { case touch, keyboard }

@MainActor @Observable final class TimerModel {
    static let startDelayKey = "timer.startDelayTenths"
    static let defaultStartDelayTenths = 2
    var mode = ScrambleMode.standard
    var standardEvent = ScrambleCatalog.restored("scramble.standard", training: false) {
        didSet { UserDefaults.standard.set(standardEvent, forKey: "scramble.standard") }
    }
    var trainingEvent = ScrambleCatalog.restored("scramble.training", training: true) {
        didSet { UserDefaults.standard.set(trainingEvent, forKey: "scramble.training") }
    }
    var event: String { mode == .standard ? standardEvent : trainingEvent }
    var eventSelection: String {
        get { event }
        set { if mode == .standard { standardEvent = newValue } else { trainingEvent = newValue } }
    }
    private(set) var scramble: Scramble?
    private(set) var nextScramble: Scramble?
    private(set) var busy = false
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchTask: Task<Scramble, Error>?
    var error: String?
    private(set) var started: ContinuousClock.Instant?
    private(set) var isReady = false
    @ObservationIgnored private var heldInput: TimerInput?
    @ObservationIgnored private var readyAt: ContinuousClock.Instant?
    @ObservationIgnored private var readinessTask: Task<Void, Never>?
    private(set) var solves: [Solve] = []
    private(set) var groups: [SolveGroup] = []
    private(set) var selectedGroupID: String?
    private var selectionEvent: String?
    var eventGroups: [SolveGroup] { groups.filter { $0.event == event } }
    var currentGroup: SolveGroup? {
        eventGroups.first { $0.id == selectedGroupID } ?? eventGroups.first { $0.isDefault }
    }
    var groupSolves: [Solve] {
        guard let currentGroup else { return [] }
        return solves.filter {
            $0.event == event && ($0.groupID ?? SolveGroup.initialID(for: $0.event)) == currentGroup.id
        }
    }
    private var lastSolveID: Solve.ID?
    var lastSolve: Solve? {
        guard let solve = solves.first, solve.id == lastSolveID else { return nil }
        return solve
    }
    private let storage: URL
    init(storage: URL = URL.documentsDirectory.appending(path: "solves.json")) {
        self.storage = storage
        do {
            let data = try Data(contentsOf: storage)
            if let store = try? JSONDecoder().decode(ResultsStore.self, from: data) {
                solves = store.solves
                groups = store.groups
            } else {
                solves = try JSONDecoder().decode([Solve].self, from: data)
            }
        }
        catch { if FileManager.default.fileExists(atPath: storage.path) { self.error = AppLanguage.saved.text("成绩读取失败：", "Could not load results: ") + error.localizedDescription } }
        let events = Set((ScrambleCatalog.standard + ScrambleCatalog.training).map(\.id) + solves.map(\.event))
        for event in events.sorted() where !groups.contains(where: { $0.event == event }) {
            groups.append(SolveGroup(id: SolveGroup.initialID(for: event), event: event, name: "", isDefault: true))
        }
    }

    func selectGroup(_ id: String) {
        guard started == nil, eventGroups.contains(where: { $0.id == id }) else { return }
        cancelPress()
        selectedGroupID = id
        lastSolveID = nil
    }

    @discardableResult
    func saveGroup(id: String? = nil, name: String, isDefault: Bool, selectNewGroup: Bool = true) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard started == nil, SolveGroup.isValidName(name) else { return false }
        var updated = groups
        let groupID = id ?? UUID().uuidString
        if isDefault {
            for index in updated.indices where updated[index].event == event {
                updated[index].isDefault = false
            }
        }
        if let index = updated.firstIndex(where: { $0.id == groupID && $0.event == event }) {
            // An existing default remains the default until another group replaces it.
            let wasDefault = groups[index].isDefault
            updated[index].name = name
            updated[index].isDefault = isDefault || wasDefault
        } else {
            updated.append(SolveGroup(id: groupID, event: event, name: name, isDefault: isDefault))
        }
        guard save(solves, groups: updated) else { return false }
        groups = updated
        if id == nil && selectNewGroup { selectGroup(groupID) }
        return true
    }

    @discardableResult
    func moveSolves(_ ids: Set<Solve.ID>, toGroup targetID: String) -> Bool {
        guard started == nil, !ids.isEmpty, let source = currentGroup,
              let target = eventGroups.first(where: { $0.id == targetID }),
              target.id != source.id,
              ids.isSubset(of: Set(groupSolves.map(\.id))) else { return false }
        return moveStoredSolves(ids, toGroup: target.id)
    }

    @discardableResult
    func moveSolve(_ id: Solve.ID, toGroup targetID: String) -> Bool {
        guard started == nil, let solve = solves.first(where: { $0.id == id }),
              let target = groups.first(where: { $0.id == targetID && $0.event == solve.event }),
              target.id != (solve.groupID ?? SolveGroup.initialID(for: solve.event)) else { return false }
        return moveStoredSolves([id], toGroup: target.id)
    }

    private func moveStoredSolves(_ ids: Set<Solve.ID>, toGroup targetID: String) -> Bool {
        var updated = solves
        for index in updated.indices where ids.contains(updated[index].id) {
            updated[index].groupID = targetID
        }
        guard save(updated) else { return false }
        solves = updated
        if let lastSolveID, ids.contains(lastSolveID) { self.lastSolveID = nil }
        return true
    }

    @discardableResult
    func moveGroup(_ id: String, to targetID: String) -> Bool {
        guard started == nil,
              let source = eventGroups.firstIndex(where: { $0.id == id }),
              let target = eventGroups.firstIndex(where: { $0.id == targetID }),
              source != target else { return false }
        var reordered = eventGroups
        reordered.move(fromOffsets: IndexSet(integer: source), toOffset: source < target ? target + 1 : target)
        return reorderGroups(reordered.map(\.id))
    }

    @discardableResult
    func reorderGroups(_ ids: [String]) -> Bool {
        guard started == nil, ids.count == eventGroups.count, Set(ids) == Set(eventGroups.map(\.id)) else { return false }
        let reordered = ids.compactMap { id in eventGroups.first(where: { $0.id == id }) }
        var updated = groups
        let positions = groups.indices.filter { groups[$0].event == event }
        for (position, group) in zip(positions, reordered) { updated[position] = group }
        guard save(solves, groups: updated) else { return false }
        groups = updated
        return true
    }

    @discardableResult
    func deleteGroup(_ id: String) -> Bool {
        guard started == nil,
              let group = eventGroups.first(where: { $0.id == id }),
              !group.isDefault else { return false }
        let updatedGroups = groups.filter { $0.id != id }
        let updatedSolves = solves.filter {
            $0.event != event || ($0.groupID ?? SolveGroup.initialID(for: $0.event)) != id
        }
        guard save(updatedSolves, groups: updatedGroups) else { return false }
        groups = updatedGroups
        solves = updatedSolves
        if selectedGroupID == id { selectedGroupID = eventGroups.first(where: { $0.isDefault })?.id }
        if !solves.contains(where: { $0.id == lastSolveID }) { lastSolveID = nil }
        return true
    }

    func refresh(advance: Bool = false) {
        guard started == nil else { return }
        if selectionEvent != event {
            selectedGroupID = eventGroups.first(where: { $0.isDefault })?.id
            selectionEvent = event
        }
        if let lastSolve, lastSolve.event != event {
            lastSolveID = nil
        }
        cancelPress()
        generationTask?.cancel()
        let prefetched = advance ? prefetchTask : nil
        if !advance { prefetchTask?.cancel() }
        prefetchTask = nil

        if advance, let nextScramble {
            scramble = nextScramble
            self.nextScramble = nil
            busy = false
            return
        }

        nextScramble = nil
        scramble = nil
        busy = true
        let event = self.event
        generationTask = Task { [weak self] in
            do {
                let generated: Scramble
                if let prefetched, let result = try? await prefetched.value {
                    generated = result
                } else {
                    try Task.checkCancellation()
                    generated = try await Engine.scramble(event: event)
                }
                guard !Task.isCancelled, let self, self.event == event else { return }
                self.scramble = generated
                self.nextScramble = nil
                self.busy = false
            } catch {
                guard !Task.isCancelled, let self, self.event == event else { return }
                self.error = error.localizedDescription
                self.busy = false
            }
        }
    }

    private func start(at instant: ContinuousClock.Instant) {
        lastSolveID = nil
        started = instant
        guard prefetchTask == nil else { return }
        let event = self.event
        prefetchTask = Task { [weak self] in
            let generated = try await Engine.scramble(event: event)
            try Task.checkCancellation()
            if let self, self.event == event, self.started != nil {
                self.nextScramble = generated
            }
            return generated
        }
    }

    func press(_ input: TimerInput, delayTenths: Int) {
        if started != nil {
            stop()
            return
        }
        guard heldInput == nil, scramble != nil, !busy else { return }
        heldInput = input
        let delay = Duration.milliseconds(min(20, max(0, delayTenths)) * 100)
        let deadline = ContinuousClock.now.advanced(by: delay)
        readyAt = deadline
        if delay == .zero {
            isReady = true
        } else {
            readinessTask = Task { [weak self] in
                do { try await ContinuousClock().sleep(until: deadline) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.isReady = true
            }
        }
    }

    func release(_ input: TimerInput) {
        guard heldInput == input, let readyAt else { return }
        let now = ContinuousClock.now
        cancelPress()
        if now >= readyAt, scramble != nil, !busy {
            start(at: now)
        }
    }

    func cancelPress(_ input: TimerInput? = nil) {
        guard input == nil || heldInput == input else { return }
        readinessTask?.cancel()
        readinessTask = nil
        heldInput = nil
        readyAt = nil
        isReady = false
    }

    func interrupt() {
        cancelPress()
        guard started != nil else { return }
        started = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        nextScramble = nil
        error = AppLanguage.saved.text("计时因 App 进入后台或中断而取消，未保存成绩。", "Timing was interrupted. The solve was not saved.")
    }

    func activateAccessibleTimer() {
        if started != nil {
            stop()
        } else if scramble != nil, !busy {
            cancelPress()
            start(at: .now)
        }
    }

    private func stop() {
        guard let start = started else { return }
        let duration = start.duration(to: .now)
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let solve = Solve(seconds: seconds, event: event, scramble: scramble?.algorithm ?? "", groupID: currentGroup?.id)
        started = nil
        lastSolveID = solve.id
        solves.insert(solve, at: 0)
        _ = save(solves)
        refresh(advance: true)
    }

    func togglePenalty(_ penalty: SolvePenalty) {
        guard let solve = lastSolve else { return }
        togglePenalty(penalty, for: solve.id)
    }

    @discardableResult
    func togglePenalty(_ penalty: SolvePenalty, for id: Solve.ID) -> Bool {
        guard let solve = solves.first(where: { $0.id == id }) else { return false }
        return setPenalty(solve.penalty == penalty ? nil : penalty, for: id)
    }

    @discardableResult
    func setPenalty(_ penalty: SolvePenalty?, for id: Solve.ID) -> Bool {
        guard started == nil, let index = solves.firstIndex(where: { $0.id == id }) else { return false }
        cancelPress()
        var updated = solves
        updated[index].penalty = penalty
        guard save(updated) else { return false }
        solves = updated
        return true
    }

    func deleteLastSolve() {
        guard let lastSolve else { return }
        deleteSolve(lastSolve.id)
    }

    @discardableResult
    func deleteSolve(_ id: Solve.ID) -> Bool {
        deleteSolves([id])
    }

    @discardableResult
    func deleteSolves(_ ids: Set<Solve.ID>) -> Bool {
        guard started == nil, !ids.isEmpty, solves.contains(where: { ids.contains($0.id) }) else { return false }
        cancelPress()
        let updated = solves.filter { !ids.contains($0.id) }
        guard save(updated) else { return false }
        solves = updated
        if let lastSolveID, ids.contains(lastSolveID) { self.lastSolveID = nil }
        return true
    }

    private func save(_ results: [Solve], groups: [SolveGroup]? = nil) -> Bool {
        do {
            try JSONEncoder().encode(ResultsStore(solves: results, groups: groups ?? self.groups)).write(to: storage, options: .atomic)
            return true
        } catch {
            self.error = AppLanguage.saved.text("成绩保存失败：", "Could not save results: ") + error.localizedDescription
            return false
        }
    }

    static func format(_ time: Double) -> String {
        displayParts(time).joined()
    }

    static func displayParts(_ time: Double) -> [String] {
        let maximumMilliseconds = 35_999_999
        let milliseconds = Int(min(Double(maximumMilliseconds), (max(0, time) * 1_000).nextUp))
        let wholeSeconds = milliseconds / 1_000
        let hours = wholeSeconds / 3_600
        let minutes = wholeSeconds / 60 % 60
        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours):")
            parts.append(String(format: "%02d:", minutes))
        } else if minutes > 0 {
            parts.append("\(minutes):")
        }
        let seconds = wholeSeconds % 60
        parts.append(wholeSeconds < 60 ? "\(seconds)." : String(format: "%02d.", seconds))
        parts.append(String(format: "%03d", milliseconds % 1_000))
        return parts
    }
}

// Display labels reference csTimer zh-cn/en-us scrdata (GPL-3.0); see docs/scramble-names.md.
// Generation rules and stable IDs remain in the installed SDK.
enum ScrambleMode: String, CaseIterable, Identifiable {
    case standard, training
    var id: Self { self }
    var title: String { self == .standard ? "标准" : "训练" }
}
struct ScrambleChoice: Identifiable {
    let id: String
    let title: String
    let group: String
    let englishTitle: String
    let englishGroup: String

    func title(in language: AppLanguage) -> String { language.text(title, englishTitle) }
    func group(in language: AppLanguage) -> String { language.text(group, englishGroup) }
}
enum ScrambleCatalog {
    static let standard: [ScrambleChoice] = [
        .init(id: "333", title: "三阶速拧", group: "", englishTitle: "3x3x3", englishGroup: ""),
        .init(id: "222", title: "二阶速拧", group: "", englishTitle: "2x2x2", englishGroup: ""),
        .init(id: "444", title: "四阶速拧", group: "", englishTitle: "4x4x4", englishGroup: ""),
        .init(id: "555", title: "五阶速拧", group: "", englishTitle: "5x5x5", englishGroup: ""),
        .init(id: "666", title: "六阶速拧", group: "", englishTitle: "6x6x6", englishGroup: ""),
        .init(id: "777", title: "七阶速拧", group: "", englishTitle: "7x7x7", englishGroup: ""),
        .init(id: "333bld", title: "三阶盲拧", group: "", englishTitle: "3x3 bld", englishGroup: ""),
        .init(id: "333oh", title: "三阶单手", group: "", englishTitle: "3x3 oh", englishGroup: ""),
        .init(id: "clock", title: "魔表", group: "", englishTitle: "clock", englishGroup: ""),
        .init(id: "minx", title: "五魔方", group: "", englishTitle: "megaminx", englishGroup: ""),
        .init(id: "pyram", title: "金字塔", group: "", englishTitle: "pyraminx", englishGroup: ""),
        .init(id: "skewb", title: "斜转魔方", group: "", englishTitle: "skewb", englishGroup: ""),
        .init(id: "sq1", title: "Square-1", group: "", englishTitle: "sq1", englishGroup: ""),
        .init(id: "fto", title: "FTO", group: "", englishTitle: "FTO", englishGroup: ""),
        .init(id: "444bld", title: "四阶盲拧", group: "", englishTitle: "4x4 bld", englishGroup: ""),
        .init(id: "555bld", title: "五阶盲拧", group: "", englishTitle: "5x5 bld", englishGroup: ""),
    ]
    static let training: [ScrambleChoice] = [
        .init(id: "222.cll", title: "CLL", group: "2x2x2", englishTitle: "CLL", englishGroup: "2x2x2"),
        .init(id: "222.eg1", title: "EG1", group: "2x2x2", englishTitle: "EG1", englishGroup: "2x2x2"),
        .init(id: "222.eg2", title: "EG2", group: "2x2x2", englishTitle: "EG2", englishGroup: "2x2x2"),
        .init(id: "222.pbl", title: "PBL", group: "2x2x2", englishTitle: "PBL", englishGroup: "2x2x2"),
        .init(id: "222.tcll_plus", title: "TCLL+", group: "2x2x2", englishTitle: "TCLL+", englishGroup: "2x2x2"),
        .init(id: "222.tcll_minus", title: "TCLL-", group: "2x2x2", englishTitle: "TCLL-", englishGroup: "2x2x2"),
        .init(id: "222.ls", title: "LS", group: "2x2x2", englishTitle: "LS", englishGroup: "2x2x2"),
        .init(id: "222.no_bar", title: "无连色", group: "2x2x2", englishTitle: "No Bar", englishGroup: "2x2x2"),
        .init(id: "222.teg1", title: "TEG-1", group: "2x2x2", englishTitle: "TEG-1", englishGroup: "2x2x2"),
        .init(id: "222.teg2", title: "TEG-2", group: "2x2x2", englishTitle: "TEG-2", englishGroup: "2x2x2"),
        .init(id: "333.edges_only", title: "棱块训练", group: "3x3x3", englishTitle: "edges only", englishGroup: "3x3x3"),
        .init(id: "333.corners_only", title: "角块训练", group: "3x3x3", englishTitle: "corners only", englishGroup: "3x3x3"),
        .init(id: "333.ll", title: "顶层训练", group: "3x3x3 CFOP", englishTitle: "last layer", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.pll", title: "PLL", group: "3x3x3 CFOP", englishTitle: "PLL", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.oll", title: "OLL", group: "3x3x3 CFOP", englishTitle: "OLL", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.lsll", title: "F2L单组", group: "3x3x3 CFOP", englishTitle: "last slot + last layer", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.zbll", title: "ZBLL", group: "3x3x3 CFOP", englishTitle: "ZBLL", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.coll", title: "COLL", group: "3x3x3 CFOP", englishTitle: "COLL", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.cll", title: "CLL", group: "3x3x3 CFOP", englishTitle: "CLL", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.ell", title: "ELL", group: "3x3x3 CFOP", englishTitle: "ELL", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.2gll", title: "2GLL", group: "3x3x3 CFOP", englishTitle: "2GLL", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.zzll", title: "ZZLL", group: "3x3x3 CFOP", englishTitle: "ZZLL", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.zbls", title: "ZBLS", group: "3x3x3 CFOP", englishTitle: "ZBLS", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.eols", title: "EOLS", group: "3x3x3 CFOP", englishTitle: "EOLS", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.wvls", title: "WVLS", group: "3x3x3 CFOP", englishTitle: "WVLS", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.vls", title: "VLS", group: "3x3x3 CFOP", englishTitle: "VLS", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.f2l", title: "F2L训练", group: "3x3x3 CFOP", englishTitle: "cross solved", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.easy_cross", title: "简单十字", group: "3x3x3 CFOP", englishTitle: "easy cross", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.easy_xcross", title: "简单XCross", group: "3x3x3 CFOP", englishTitle: "easy xcross", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.eoline", title: "EOLine", group: "3x3x3 CFOP", englishTitle: "EOLine", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.eo_cross", title: "EO Cross", group: "3x3x3 CFOP", englishTitle: "EO Cross", englishGroup: "3x3x3 CFOP"),
        .init(id: "333.edge_permutation", title: "棱块排列", group: "3x3x3 状态训练", englishTitle: "edge permutation", englishGroup: "3x3x3 state training"),
        .init(id: "333.edge_orientation", title: "棱块朝向", group: "3x3x3 状态训练", englishTitle: "edge orientation", englishGroup: "3x3x3 state training"),
        .init(id: "333.corner_permutation", title: "角块排列", group: "3x3x3 状态训练", englishTitle: "corner permutation", englishGroup: "3x3x3 state training"),
        .init(id: "333.corner_orientation", title: "角块朝向", group: "3x3x3 状态训练", englishTitle: "corner orientation", englishGroup: "3x3x3 state training"),
        .init(id: "333.permutation_only", title: "仅排列", group: "3x3x3 状态训练", englishTitle: "permutation only", englishGroup: "3x3x3 state training"),
        .init(id: "333.orientation_only", title: "仅朝向", group: "3x3x3 状态训练", englishTitle: "orientation only", englishGroup: "3x3x3 state training"),
        .init(id: "333.three_edge_cycle", title: "三棱循环", group: "3x3x3 状态训练", englishTitle: "three edge cycle", englishGroup: "3x3x3 state training"),
        .init(id: "333.three_corner_cycle", title: "三角循环", group: "3x3x3 状态训练", englishTitle: "three corner cycle", englishGroup: "3x3x3 state training"),
        .init(id: "333.roux.second_block", title: "2nd Block", group: "3x3x3 Roux", englishTitle: "2nd Block", englishGroup: "3x3x3 Roux"),
        .init(id: "333.roux.cmll", title: "CMLL", group: "3x3x3 Roux", englishTitle: "CMLL", englishGroup: "3x3x3 Roux"),
        .init(id: "333.roux.lse", title: "LSE", group: "3x3x3 Roux", englishTitle: "LSE", englishGroup: "3x3x3 Roux"),
        .init(id: "333.roux.lse_mu", title: "LSE <M, U>", group: "3x3x3 Roux", englishTitle: "LSE <M, U>", englishGroup: "3x3x3 Roux"),
        .init(id: "333.mehta.3qb", title: "3QB", group: "3x3x3 Mehta", englishTitle: "3QB", englishGroup: "3x3x3 Mehta"),
        .init(id: "333.mehta.eole", title: "EOLE", group: "3x3x3 Mehta", englishTitle: "EOLE", englishGroup: "3x3x3 Mehta"),
        .init(id: "333.mehta.tdr", title: "TDR", group: "3x3x3 Mehta", englishTitle: "TDR", englishGroup: "3x3x3 Mehta"),
        .init(id: "333.mehta.6cp", title: "6CP", group: "3x3x3 Mehta", englishTitle: "6CP", englishGroup: "3x3x3 Mehta"),
        .init(id: "333.mehta.cdrll", title: "CDRLL", group: "3x3x3 Mehta", englishTitle: "CDRLL", englishGroup: "3x3x3 Mehta"),
        .init(id: "333.mehta.l5ep", title: "L5EP", group: "3x3x3 Mehta", englishTitle: "L5EP", englishGroup: "3x3x3 Mehta"),
        .init(id: "333.mehta.ttll", title: "TTLL", group: "3x3x3 Mehta", englishTitle: "TTLL", englishGroup: "3x3x3 Mehta"),
        .init(id: "333.subset.ru", title: "2-generator R,U", group: "3x3x3子集", englishTitle: "2-generator R,U", englishGroup: "3x3x3 subsets"),
        .init(id: "333.subset.lu", title: "2-generator L,U", group: "3x3x3子集", englishTitle: "2-generator L,U", englishGroup: "3x3x3 subsets"),
        .init(id: "333.subset.fru", title: "3-generator F,R,U", group: "3x3x3子集", englishTitle: "3-generator F,R,U", englishGroup: "3x3x3 subsets"),
        .init(id: "333.subset.rul", title: "3-generator R,U,L", group: "3x3x3子集", englishTitle: "3-generator R,U,L", englishGroup: "3x3x3 subsets"),
        .init(id: "333.subset.rrwu", title: "3-generator R,r,U", group: "3x3x3子集", englishTitle: "3-generator R,r,U", englishGroup: "3x3x3 subsets"),
        .init(id: "333.subset.mu", title: "Roux-generator M,U", group: "3x3x3子集", englishTitle: "Roux-generator M,U", englishGroup: "3x3x3 subsets"),
        .init(id: "333.subset.half_turn", title: "half turns only", group: "3x3x3子集", englishTitle: "half turns only", englishGroup: "3x3x3 subsets"),
        .init(id: "333.subset.domino", title: "Domino Subgroup", group: "3x3x3子集", englishTitle: "Domino Subgroup", englishGroup: "3x3x3 subsets"),
        .init(id: "444.edge_pairing", title: "对棱训练", group: "4x4x4", englishTitle: "4x4x4 edges", englishGroup: "4x4x4"),
        .init(id: "444.subset.rruu", title: "R,r,U,u", group: "4x4x4", englishTitle: "R,r,U,u", englishGroup: "4x4x4"),
        .init(id: "444.ll", title: "Last layer", group: "4x4x4", englishTitle: "Last layer", englishGroup: "4x4x4"),
        .init(id: "444.ell", title: "ELL", group: "4x4x4", englishTitle: "ELL", englishGroup: "4x4x4"),
        .init(id: "444.edges_only", title: "Edge only", group: "4x4x4", englishTitle: "Edge only", englishGroup: "4x4x4"),
        .init(id: "444.centers_only", title: "Center only", group: "4x4x4", englishTitle: "Center only", englishGroup: "4x4x4"),
        .init(id: "444.yau.ud_centers", title: "UD center solved", group: "4x4x4 Yau/Hoya", englishTitle: "UD center solved", englishGroup: "4x4x4 Yau/Hoya"),
        .init(id: "444.yau.ud_3_edges", title: "UD+3E solved", group: "4x4x4 Yau/Hoya", englishTitle: "UD+3E solved", englishGroup: "4x4x4 Yau/Hoya"),
        .init(id: "444.yau.last_8_dedges", title: "Last 8 dedges", group: "4x4x4 Yau/Hoya", englishTitle: "Last 8 dedges", englishGroup: "4x4x4 Yau/Hoya"),
        .init(id: "444.hoya.rl_centers", title: "RL center solved", group: "4x4x4 Yau/Hoya", englishTitle: "RL center solved", englishGroup: "4x4x4 Yau/Hoya"),
        .init(id: "444.hoya.rldx_centers", title: "RLDX center solved", group: "4x4x4 Yau/Hoya", englishTitle: "RLDX center solved", englishGroup: "4x4x4 Yau/Hoya"),
        .init(id: "444.hoya.rldx_cross", title: "RLDX cross solved", group: "4x4x4 Yau/Hoya", englishTitle: "RLDX cross solved", englishGroup: "4x4x4 Yau/Hoya"),
        .init(id: "444.poll", title: "POLL", group: "4x4x4 Yau/Hoya", englishTitle: "POLL", englishGroup: "4x4x4 Yau/Hoya"),
        .init(id: "444.ppll", title: "PPLL", group: "4x4x4 Yau/Hoya", englishTitle: "PPLL", englishGroup: "4x4x4 Yau/Hoya"),
        .init(id: "555.edge_pairing", title: "对棱训练", group: "5x5x5", englishTitle: "5x5x5 edges", englishGroup: "5x5x5"),
        .init(id: "666.edge_pairing", title: "对棱训练", group: "6x6x6", englishTitle: "6x6x6 edges", englishGroup: "6x6x6"),
        .init(id: "777.edge_pairing", title: "对棱训练", group: "7x7x7", englishTitle: "7x7x7 edges", englishGroup: "7x7x7"),
        .init(id: "minx.subset.ru", title: "2-generator R,U", group: "五魔方", englishTitle: "2-generator R,U", englishGroup: "Megaminx"),
        .init(id: "minx.s2l", title: "S2L", group: "五魔方", englishTitle: "S2L", englishGroup: "Megaminx"),
        .init(id: "minx.lsll", title: "last slot + last layer", group: "五魔方", englishTitle: "last slot + last layer", englishGroup: "Megaminx"),
        .init(id: "minx.pll", title: "PLL", group: "五魔方", englishTitle: "PLL", englishGroup: "Megaminx"),
        .init(id: "minx.ll", title: "Last Layer", group: "五魔方", englishTitle: "Last Layer", englishGroup: "Megaminx"),
        .init(id: "pyram.l4e", title: "L4E", group: "金字塔", englishTitle: "L4E", englishGroup: "Pyraminx"),
        .init(id: "pyram.four_tips", title: "4 tips", group: "金字塔", englishTitle: "4 tips", englishGroup: "Pyraminx"),
        .init(id: "pyram.no_bar", title: "No bar", group: "金字塔", englishTitle: "No bar", englishGroup: "Pyraminx"),
        .init(id: "skewb.l2l", title: "顶层训练", group: "Skewb", englishTitle: "last layer", englishGroup: "Skewb"),
        .init(id: "skewb.no_bar", title: "No bar", group: "Skewb", englishTitle: "No bar", englishGroup: "Skewb"),
        .init(id: "sq1.cube_shape", title: "方形状态", group: "Square-1", englishTitle: "Cube shape", englishGroup: "Square-1"),
        .init(id: "sq1.csp", title: "CSP", group: "Square-1", englishTitle: "CSP", englishGroup: "Square-1"),
        .init(id: "sq1.pbl", title: "PBL", group: "Square-1", englishTitle: "PBL", englishGroup: "Square-1"),
        .init(id: "fto.l3t", title: "L3T", group: "FTO", englishTitle: "L3T", englishGroup: "FTO (Face-Turning Octahedron)"),
        .init(id: "fto.l3t_lbt", title: "L3T+LBT", group: "FTO", englishTitle: "L3T+LBT", englishGroup: "FTO (Face-Turning Octahedron)"),
        .init(id: "fto.tcp", title: "TCP", group: "FTO", englishTitle: "TCP", englishGroup: "FTO (Face-Turning Octahedron)"),
        .init(id: "fto.edges_only", title: "edges only", group: "FTO", englishTitle: "edges only", englishGroup: "FTO (Face-Turning Octahedron)"),
        .init(id: "fto.centers_only", title: "centers only", group: "FTO", englishTitle: "centers only", englishGroup: "FTO (Face-Turning Octahedron)"),
        .init(id: "fto.corners_only", title: "corners only", group: "FTO", englishTitle: "corners only", englishGroup: "FTO (Face-Turning Octahedron)"),
    ]
    static func trainingGroups(in language: AppLanguage) -> [String] {
        training.reduce(into: []) { groups, choice in
            let group = choice.group(in: language)
            if !groups.contains(group) { groups.append(group) }
        }
    }
    static func title(_ id: String, in language: AppLanguage) -> String {
        guard let choice = (standard + training).first(where: { $0.id == id }) else { return id }
        let group = choice.group(in: language)
        let title = choice.title(in: language)
        return group.isEmpty ? title : "\(group) · \(title)"
    }
    static func trainingSelectionTitle(_ id: String, in language: AppLanguage) -> String? {
        training.first(where: { $0.id == id })?.title(in: language)
            .replacingOccurrences(of: "2-generator ", with: "")
            .replacingOccurrences(of: "3-generator ", with: "")
            .replacingOccurrences(of: "Roux-generator ", with: "")
    }
    static func restored(_ key: String, training isTraining: Bool) -> String {
        let choices = isTraining ? training : standard
        let saved = UserDefaults.standard.string(forKey: key) ?? ""
        return choices.contains(where: { $0.id == saved }) ? saved : (isTraining ? "333.pll" : "333")
    }
}

struct ResultExtremes: Sendable {
    static let includeDNFPreferenceKey = "results.includeDNFInWorst"
    static let defaultIncludesDNF = true

    let includesDNF: Bool
    private(set) var best: Int?
    private(set) var worst: Int?
    private var bestTime = Double.infinity
    private var worstTime = -Double.infinity

    init(includesDNF: Bool) {
        self.includesDNF = includesDNF
    }

    // Results arrive newest first. For ties, mark the oldest best and newest worst.
    mutating func record(_ time: Double?, at index: Int, tolerance: Double = 0) {
        guard time != nil || includesDNF else { return }
        let time = time ?? .infinity
        if time.isFinite, time <= bestTime + tolerance {
            best = index
            bestTime = min(bestTime, time)
        }
        if time > worstTime + tolerance {
            worst = index
            worstTime = time
        }
    }
}

enum SolveAverage: Int, CaseIterable, Sendable {
    case mo3 = 3, ao5 = 5, ao12 = 12, ao50 = 50, ao100 = 100, ao500 = 500, ao1000 = 1000, ao10000 = 10000

    var count: Int { rawValue }
    var title: String { self == .mo3 ? "mo3" : "ao\(count)" }
    private var trim: Int { self == .mo3 ? 0 : (count + 19) / 20 }

    struct Summary {
        let mean: Double?
        let standardDeviation: Double?
        let hasDNF: Bool
    }

    @concurrent func rollingExtremes(_ times: [Double?], includesDNF: Bool) async -> ResultExtremes {
        var extremes = ResultExtremes(includesDNF: includesDNF)
        forEachRollingMean(times) { start, mean in
            extremes.record(mean, at: start, tolerance: 1e-9)
        }
        return Task.isCancelled ? ResultExtremes(includesDNF: includesDNF) : extremes
    }

    // Input is newest first. Each mean belongs to the newest solve in its window.
    nonisolated func forEachRollingMean(_ times: [Double?], _ visit: (Int, Double?) -> Void) {
        guard times.count >= count else { return }

        // Rank the times once, then keep counts and sums in a Fenwick tree as the window moves.
        let ordered = times.indices.sorted { (times[$0] ?? .infinity) < (times[$1] ?? .infinity) }
        var ranks = Array(repeating: 0, count: times.count)
        for (rank, index) in ordered.enumerated() {
            ranks[index] = rank + 1
        }
        var counts = Array(repeating: 0, count: times.count + 1)
        var sums = Array(repeating: 0.0, count: times.count + 1)
        var dnfs = 0
        func update(_ index: Int, by delta: Int) {
            if times[index] == nil { dnfs += delta }
            let change = (times[index] ?? 0) * Double(delta)
            var node = ranks[index]
            while node < counts.count {
                counts[node] += delta
                sums[node] += change
                node += node & -node
            }
        }
        let highestBit = 1 << (Int.bitWidth - 1 - times.count.leadingZeroBitCount)
        func sumOfFastest(_ count: Int) -> Double {
            var rank = 0
            var remaining = count
            var sum = 0.0
            var bit = highestBit
            while bit > 0 {
                let next = rank + bit
                if next < counts.count, counts[next] <= remaining {
                    rank = next
                    remaining -= counts[next]
                    sum += sums[next]
                }
                bit >>= 1
            }
            return sum
        }

        for index in 0..<count { update(index, by: 1) }
        for start in 0...(times.count - count) {
            guard !Task.isCancelled else { return }
            if dnfs > trim {
                visit(start, nil)
            } else {
                let sum = sumOfFastest(count - trim) - sumOfFastest(trim)
                let mean = sum / Double(count - 2 * trim)
                visit(start, mean)
            }
            let next = start + count
            if next < times.count {
                update(start, by: -1)
                update(next, by: 1)
            }
        }
    }

    // The caller supplies a complete rolling window of this size.
    func summarize(_ solves: ArraySlice<Solve>) -> Summary {
        precondition(solves.count == count)
        let sorted = solves.map { $0.resultSeconds ?? .infinity }.sorted()
        let kept = sorted.dropFirst(trim).dropLast(trim)
        let hasDNF = sorted.last == .infinity
        guard kept.last != .infinity else {
            return Summary(mean: nil, standardDeviation: nil, hasDNF: hasDNF)
        }
        let mean = kept.reduce(0, +) / Double(kept.count)
        let variance = kept.reduce(0.0) { sum, time in
            let difference = time - mean
            return sum + difference * difference
        } / Double(kept.count)
        return Summary(mean: mean, standardDeviation: variance.squareRoot(), hasDNF: hasDNF)
    }
}
