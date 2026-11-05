import Foundation
#if canImport(Cubegin)
import Cubegin
#endif

struct Scramble: Sendable { let algorithm: String; let svg: String }
enum Engine {
    static func diagram(event: String, algorithm: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
#if canImport(Cubegin)
            let baseEvent = String(event.split(separator: ".")[0])
            return try evaluateEvent(event: baseEvent, algorithm: algorithm).svg
#else
            throw EngineError.sdkMissing
#endif
        }.value
    }

    static func scramble(event: String) async throws -> Scramble {
        try await Task.detached(priority: .userInitiated) {
#if canImport(Cubegin)
            let seed = UInt32.random(in: .min ... .max)
            let algorithm: String
            if event.contains(".") {
                struct TrainingResult: Decodable { let algorithm: String }
                let json = try generateTraining(id: event, seed: seed, optionsJson: "{}")
                algorithm = try JSONDecoder().decode(TrainingResult.self, from: Data(json.utf8)).algorithm
            } else {
                algorithm = try generateEvent(event: event, seed: seed).algorithm
            }
            let baseEvent = String(event.split(separator: ".")[0])
            let state = try evaluateEvent(event: baseEvent, algorithm: algorithm)
            return Scramble(algorithm: algorithm, svg: state.svg)
#else
            throw EngineError.sdkMissing
#endif
        }.value
    }
    enum EngineError: LocalizedError {
        case sdkMissing
        var errorDescription: String? { "尚未链接 Cubegin SDK。请构建 cubegin-core 的 iOS XCFramework，然后打开 Cubegin.xcodeproj 使用 CubeginApp scheme。" }
    }
}
