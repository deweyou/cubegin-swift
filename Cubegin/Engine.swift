import Foundation
#if canImport(Cubegin)
import Cubegin
#endif

struct Scramble: Sendable { let algorithm: String; let svg: String }
enum Engine {
    static func scramble(event: String) async throws -> Scramble {
        try await Task.detached(priority: .userInitiated) {
#if canImport(Cubegin)
            let result = try generateEvent(event: event, seed: UInt32.random(in: .min ... .max))
            let state = try evaluateEvent(event: event, algorithm: result.algorithm)
            return Scramble(algorithm: result.algorithm, svg: state.svg)
#else
            throw EngineError.sdkMissing
#endif
        }.value
    }
    static func cross(algorithm: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
#if canImport(Cubegin)
            return try solveAssist(event: "333", methodsJson: "[\"cross\"]", algorithm: algorithm, optionsJson: "{\"max_depth\":12}")
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
