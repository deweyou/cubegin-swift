import Foundation
import Testing
@testable import CubeginApp

struct SolveAverageTests {
    @Test func ao5TrimsExtremesAndUsesPenalizedTimesForMeanAndDeviation() throws {
        let solves = [
            solve(7), solve(10, penalty: .plusTwo), solve(13), solve(14), solve(6, penalty: .dnf),
        ]
        let summary = SolveAverage.ao5.summarize(solves[...])
        #expect(summary.hasDNF)
        #expect(summary.mean == 13)
        let deviation = try #require(summary.standardDeviation)
        #expect(abs(deviation - 0.816496580927726) < 1e-12)
    }

    @Test func mo3KeepsEveryTimeAndDNFInvalidatesTheWindow() {
        let valid = [solve(9), solve(12), solve(15)]
        let summary = SolveAverage.mo3.summarize(valid[...])
        #expect(summary.mean == 12)
        #expect(!summary.hasDNF)

        let invalid = [solve(9), solve(12), solve(15, penalty: .dnf)]
        let dnf = SolveAverage.mo3.summarize(invalid[...])
        #expect(dnf.hasDNF)
        #expect(dnf.mean == nil)
        #expect(dnf.standardDeviation == nil)
    }

    @Test(arguments: [(.mo3, 0), (.ao5, 1), (.ao12, 1), (.ao50, 3), (.ao100, 5),
                      (.ao500, 25), (.ao1000, 50), (.ao10000, 500)] as [(SolveAverage, Int)])
    func rollingWindowsMatchAnIndependentSortedReference(kind: SolveAverage, trim: Int) {
        var times: [Double?] = (0..<(kind.count + 4)).map { 8 + Double($0 % 31) / 4 }
        for index in 0...trim { times[index] = nil }

        var visited: [Int] = []
        kind.forEachRollingMean(times) { start, actual in
            visited.append(start)
            let window = times[start..<(start + kind.count)]
            let valid = window.compactMap { $0 }.sorted()
            let dnfs = kind.count - valid.count
            if dnfs > trim {
                #expect(actual == nil)
            } else {
                let retained = valid.dropFirst(trim).dropLast(trim - dnfs)
                let expected = retained.reduce(0, +) / Double(retained.count)
                #expect(actual.map { abs($0 - expected) < 1e-9 } == true)
            }
        }
        #expect(visited == [0, 1, 2, 3, 4])

        var visitedIncompleteWindow = false
        kind.forEachRollingMean(Array(times.prefix(kind.count - 1))) { _, _ in
            visitedIncompleteWindow = true
        }
        #expect(!visitedIncompleteWindow)
    }

    @Test func rollingExtremesHandleDNFPreferenceAndTies() async {
        let times: [Double?] = [nil, 10, 10, 10, 10]
        let includingDNF = await SolveAverage.mo3.rollingExtremes(times, includesDNF: true)
        #expect(includingDNF.best == 2)
        #expect(includingDNF.worst == 0)

        let excludingDNF = await SolveAverage.mo3.rollingExtremes(times, includesDNF: false)
        #expect(excludingDNF.best == 2)
        #expect(excludingDNF.worst == 1)
    }

    private func solve(_ seconds: Double, penalty: SolvePenalty? = nil) -> Solve {
        Solve(seconds: seconds, event: "333", scramble: "R", penalty: penalty)
    }
}
