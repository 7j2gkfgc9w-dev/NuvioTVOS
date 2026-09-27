import Foundation
import CoreGraphics
import AetherEngine

@MainActor
protocol SceneFrameProviding: AnyObject {
    var isSupported: Bool { get }
    var capabilityMessage: String? { get }
    func captureCurrentFrame(maxWidth: Int, context: SceneContext) -> SceneFrame?
}

@MainActor
final class AetherSceneFrameProvider: SceneFrameProviding {
    private weak var aetherController: AetherPlaybackController?
    
    init(controller: AetherPlaybackController?) {
        self.aetherController = controller
    }
    
    var isSupported: Bool {
        aetherController != nil
    }
    
    var capabilityMessage: String? {
        if aetherController == nil {
            return "Aether engine not active"
        }
        return nil
    }
    
    func captureCurrentFrame(maxWidth: Int = 960, context: SceneContext) -> SceneFrame? {
        guard let controller = aetherController else { return nil }
        // Capture directly from the active display pipeline in presentation memory
        guard let image = controller.engine.captureCurrentVideoFrame(maxWidth: maxWidth) else {
            return nil
        }
        let sourceTime = controller.engine.sourceTime
        return SceneFrame(
            image: image,
            sourceTime: sourceTime,
            sessionID: context.sessionID,
            generation: context.timelineGeneration
        )
    }
}

@MainActor
final class UnsupportedSceneFrameProvider: SceneFrameProviding {
    private let reason: String
    
    init(reason: String = "Current playback backend does not support direct display pipeline frame capture.") {
        self.reason = reason
    }
    
    var isSupported: Bool { false }
    var capabilityMessage: String? { reason }
    
    func captureCurrentFrame(maxWidth: Int, context: SceneContext) -> SceneFrame? {
        return nil
    }
}

@MainActor
final class DynamicPlayerSceneFrameProvider: SceneFrameProviding {
    private let activeEngineKindProvider: () -> PlayerBackendKind
    private let aetherControllerProvider: () -> AetherPlaybackController?
    
    init(
        activeEngineKindProvider: @escaping () -> PlayerBackendKind,
        aetherControllerProvider: @escaping () -> AetherPlaybackController?
    ) {
        self.activeEngineKindProvider = activeEngineKindProvider
        self.aetherControllerProvider = aetherControllerProvider
    }
    
    var isSupported: Bool {
        activeEngineKindProvider() == .aether && aetherControllerProvider() != nil
    }
    
    var capabilityMessage: String? {
        if activeEngineKindProvider() == .mpv {
            return "MPV backend does not support direct display pipeline frame capture."
        }
        if aetherControllerProvider() == nil {
            return "Aether engine not active"
        }
        return nil
    }
    
    func captureCurrentFrame(maxWidth: Int = 960, context: SceneContext) -> SceneFrame? {
        guard activeEngineKindProvider() == .aether,
              let controller = aetherControllerProvider() else {
            return nil
        }
        guard let image = controller.engine.captureCurrentVideoFrame(maxWidth: maxWidth) else {
            return nil
        }
        let sourceTime = controller.engine.sourceTime
        return SceneFrame(
            image: image,
            sourceTime: sourceTime,
            sessionID: context.sessionID,
            generation: context.timelineGeneration
        )
    }
}
