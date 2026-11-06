import Foundation
import Testing
@testable import CubeginApp

@MainActor
struct TimerModelTests {
    @Test func holdReleaseAndStopPersistTheOriginalScrambleAndExactTime() async throws {
        try await withFixture { fixture in
            var now = ContinuousClock.now
            let model = fixture.model(now: { now })
            model.refresh()
            try await waitForGeneration(model)
            let original = try #require(model.scramble)
            #expect(model.saveGroup(name: "Practice", isDefault: false))
            let group = try #require(model.currentGroup)

            model.press(.touch, delayTenths: 2)
            now += .milliseconds(199)
            model.release(.touch)
            #expect(model.started == nil)

            model.press(.keyboard, delayTenths: 2)
            now += .milliseconds(200)
            model.release(.touch)
            #expect(model.started == nil)
            model.release(.keyboard)
            #expect(model.started == now)
            try await waitForPrefetch(model)
            let prefetched = try #require(model.nextScramble)
            #expect(prefetched.algorithm != original.algorithm)

            now += .milliseconds(12_345)
            model.press(.touch, delayTenths: 2)
            #expect(model.started == nil)
            let solve = try #require(model.lastSolve)
            #expect(solve.seconds == 12.345)
            #expect(solve.event == "333")
            #expect(solve.groupID == group.id)
            #expect(solve.scramble == original.algorithm)
            #expect(model.scramble?.algorithm == prefetched.algorithm)
            #expect(model.nextScramble == nil)
            #expect(fixture.model().solves == [solve])
        }
    }

    @Test func interruptedAttemptAndCancelledHoldDoNotSave() async throws {
        try await withFixture { fixture in
            let model = fixture.model()
            model.refresh()
            try await waitForGeneration(model)

            model.press(.touch, delayTenths: 0)
            #expect(model.isReady)
            model.cancelPress(.touch)
            model.release(.touch)
            #expect(!model.isReady)
            #expect(model.started == nil)

            model.activateAccessibleTimer()
            #expect(model.started != nil)
            try await waitForPrefetch(model)
            model.interrupt()
            #expect(model.started == nil)
            #expect(model.nextScramble == nil)
            #expect(model.error != nil)
            #expect(model.solves.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: fixture.storage.path))
        }
    }

    @Test func eventSwitchDiscardsPrefetchAndRestoresEachModeSelection() async throws {
        try await withFixture { fixture in
            let model = fixture.model()
            model.refresh()
            try await waitForGeneration(model)
            model.activateAccessibleTimer()
            try await waitForPrefetch(model)
            model.activateAccessibleTimer()

            model.eventSelection = "222"
            model.refresh()
            try await waitForGeneration(model)
            #expect(model.scramble?.algorithm.hasPrefix("222:") == true)
            #expect(model.lastSolve == nil)

            model.mode = .training
            model.eventSelection = "333.oll"
            model.refresh()
            try await waitForGeneration(model)
            #expect(model.scramble?.algorithm.hasPrefix("333.oll:") == true)
            #expect(model.currentGroup?.id == "default:333.oll")

            let reopened = fixture.model()
            #expect(reopened.mode == .standard)
            #expect(reopened.event == "222")
            reopened.mode = .training
            #expect(reopened.event == "333.oll")
        }
    }

    @Test func legacySolvesSurviveGroupEditsMovesAndPenalties() async throws {
        try await withFixture { fixture in
            let first = Solve(seconds: 13.25, event: "333", scramble: "R U", date: Date(timeIntervalSince1970: 100))
            let second = Solve(seconds: 15, event: "333", scramble: "F U", date: Date(timeIntervalSince1970: 90))
            let unrelated = Solve(seconds: 8, event: "222", scramble: "R2", date: Date(timeIntervalSince1970: 80))
            try JSONEncoder().encode([first, second, unrelated]).write(to: fixture.storage)
            let model = fixture.model()
            let initial = try #require(model.currentGroup)
            #expect(initial.id == "default:333")
            #expect(model.groupSolves == [first, second])

            #expect(!model.saveGroup(name: "Line\nbreak", isDefault: false))
            #expect(model.saveGroup(name: "  Practice  ", isDefault: true))
            let practice = try #require(model.currentGroup)
            #expect(practice.name == "Practice")
            #expect(model.eventGroups.filter(\.isDefault).map(\.id) == [practice.id])
            #expect(!model.deleteGroup(practice.id))
            #expect(!model.reorderGroups([practice.id, practice.id]))
            #expect(model.moveGroup(practice.id, to: initial.id))
            model.selectGroup(initial.id)
            #expect(!model.moveSolves([first.id, unrelated.id], toGroup: practice.id))
            #expect(!model.moveSolve(first.id, toGroup: "default:222"))
            #expect(model.moveSolves([first.id, second.id], toGroup: practice.id))
            #expect(model.groupSolves.isEmpty)

            #expect(model.togglePenalty(.plusTwo, for: first.id))
            #expect(model.solves.first?.resultSeconds == 15.25)
            #expect(model.togglePenalty(.dnf, for: first.id))
            #expect(model.solves.first?.resultSeconds == nil)
            #expect(model.togglePenalty(.dnf, for: first.id))
            #expect(model.solves.first?.resultSeconds == first.seconds)

            let reopened = fixture.model()
            #expect(reopened.eventGroups.map(\.id) == [practice.id, initial.id])
            #expect(reopened.groupSolves.map(\.id) == [first.id, second.id])
            #expect(reopened.groupSolves.first?.scramble == first.scramble)
            #expect(reopened.groupSolves.first?.date == first.date)
            #expect(reopened.moveSolve(first.id, toGroup: initial.id))
            #expect(reopened.deleteSolves([second.id]))
            #expect(reopened.saveGroup(id: initial.id, name: "Restored", isDefault: true))
            reopened.selectGroup(practice.id)
            #expect(reopened.deleteGroup(practice.id))
            #expect(reopened.currentGroup?.id == initial.id)
            #expect(fixture.model().solves.map(\.id) == [first.id, unrelated.id])
        }
    }

    @Test func groupDeletionRemovesOnlyItsOwnSolves() async throws {
        try await withFixture { fixture in
            let keep = Solve(seconds: 10, event: "333", scramble: "R")
            let remove = Solve(seconds: 11, event: "333", scramble: "U")
            try JSONEncoder().encode([keep, remove]).write(to: fixture.storage)
            let model = fixture.model()
            #expect(model.saveGroup(name: "Disposable", isDefault: false))
            let group = try #require(model.currentGroup)
            #expect(model.moveSolve(remove.id, toGroup: group.id))
            #expect(model.deleteGroup(group.id))
            #expect(model.currentGroup?.id == "default:333")
            #expect(fixture.model().solves == [keep])
        }
    }

    @Test func failedStorageWriteLeavesGroupAndSolveEditsUnapplied() async throws {
        try await withFixture { fixture in
            let solve = Solve(seconds: 10, event: "333", scramble: "R")
            try JSONEncoder().encode([solve]).write(to: fixture.storage)
            let model = fixture.model()
            try FileManager.default.removeItem(at: fixture.directory)
            #expect(!model.setPenalty(.plusTwo, for: solve.id))
            #expect(!model.deleteSolve(solve.id))
            #expect(!model.saveGroup(name: "Practice", isDefault: true))
            #expect(model.error != nil)
            #expect(model.solves == [solve])
            #expect(model.eventGroups.map(\.id) == ["default:333"])
        }
    }

    @Test func corruptHistoryReportsAReadError() async throws {
        try await withFixture { fixture in
            try Data("{invalid JSON".utf8).write(to: fixture.storage)
            let model = fixture.model()
            #expect(model.error != nil)
            #expect(model.solves.isEmpty)
            #expect(model.currentGroup?.id == "default:333")
        }
    }

    @Test func timerDisplayTruncatesAtMillisecondsAndFormatsBoundaries() {
        #expect(TimerModel.format(-1) == "0.000")
        #expect(TimerModel.format(59.9999) == "59.999")
        #expect(TimerModel.format(60.001) == "1:00.001")
        #expect(TimerModel.format(3_605.125) == "1:00:05.125")
        #expect(TimerModel.format(36_000) == "9:59:59.999")
    }

    private func waitForGeneration(_ model: TimerModel) async throws {
        try await waitUntil { !model.busy }
        _ = try #require(model.scramble)
    }

    private func waitForPrefetch(_ model: TimerModel) async throws {
        try await waitUntil { model.nextScramble != nil }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Scramble generation did not reach the expected state")
    }

    private func withFixture(_ body: @MainActor (Fixture) async throws -> Void) async throws {
        let name = "CubeginTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try await body(Fixture(directory: directory, defaults: defaults))
    }

    private struct Fixture {
        let directory: URL
        let defaults: UserDefaults
        var storage: URL { directory.appending(path: "solves.json") }

        @MainActor func model(now: @escaping () -> ContinuousClock.Instant = { .now }) -> TimerModel {
            let generator = ScrambleGenerator()
            return TimerModel(storage: storage, defaults: defaults, now: now) { event in
                await generator.generate(event)
            }
        }
    }

    private actor ScrambleGenerator {
        private var count = 0

        func generate(_ event: String) -> Scramble {
            count += 1
            return Scramble(algorithm: "\(event):\(count)", svg: "")
        }
    }
}
