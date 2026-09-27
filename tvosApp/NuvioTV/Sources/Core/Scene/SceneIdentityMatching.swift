import Foundation
import CoreGraphics
import Vision
import CoreML

// MARK: - Face Representation

enum SceneFaceRepresentation: @unchecked Sendable {
    case visionFeaturePrint(VNFeaturePrintObservation)
    case coreMLEmbedding([Float])
}

enum SceneMatchingError: LocalizedError {
    case featurePrintGenerationFailed
    case incompatibleRepresentations
    case modelExecutionFailed
    
    var errorDescription: String? {
        switch self {
        case .featurePrintGenerationFailed:
            return "Failed to generate Apple Vision feature print."
        case .incompatibleRepresentations:
            return "Representations from different matchers cannot be compared."
        case .modelExecutionFailed:
            return "Core ML face embedding model failed."
        }
    }
}

// MARK: - Identity Matching Protocol

protocol SceneIdentityMatching: Sendable {
    var matcherIdentifier: String { get }
    var defaultAcceptanceDistance: Float { get }
    var defaultMarginDistance: Float { get }
    
    /// Computes a feature representation for a cropped face image.
    func computeFaceRepresentation(for croppedFace: CGImage) async throws -> SceneFaceRepresentation
    
    /// Computes distance between two representations. Lower distance means higher similarity.
    func computeDistance(between query: SceneFaceRepresentation, reference: SceneFaceRepresentation) throws -> Float
}

// MARK: - Native Apple Vision Feature-Print Matcher

final class VisionFeaturePrintMatcher: SceneIdentityMatching {
    let matcherIdentifier: String = "apple-vision-featureprint-v1"
    
    // Calibrated L2 distance thresholds for Apple Vision FeaturePrint:
    // Video frames vs. studio portraits typical distance: 0.70 - 0.90
    let defaultAcceptanceDistance: Float = 0.92
    let defaultMarginDistance: Float = 0.04
    
    init() {}
    
    func computeFaceRepresentation(for croppedFace: CGImage) async throws -> SceneFaceRepresentation {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit

        #if targetEnvironment(simulator)
        if #available(tvOS 17.0, *) {
            var configuredCPUStages = 0
            if let supportedStages = try? request.supportedComputeStageDevices {
                for (stage, devices) in supportedStages {
                    guard let cpuDevice = devices.first(where: { device in
                        if case .cpu = device { return true }
                        return false
                    }) else {
                        continue
                    }

                    request.setComputeDevice(cpuDevice, for: stage)
                    configuredCPUStages += 1
                }
            }
            if configuredCPUStages == 0 {
                print("[ActorRecognition] Vision feature-print request exposes no CPU compute stages on simulator")
            }
        }
        #endif
        
        let handler = VNImageRequestHandler(cgImage: croppedFace, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first as? VNFeaturePrintObservation else {
            throw SceneMatchingError.featurePrintGenerationFailed
        }
        return .visionFeaturePrint(result)
    }
    
    func computeDistance(between query: SceneFaceRepresentation, reference: SceneFaceRepresentation) throws -> Float {
        guard case .visionFeaturePrint(let printA) = query,
              case .visionFeaturePrint(let printB) = reference else {
            throw SceneMatchingError.incompatibleRepresentations
        }
        var distance: Float = 0
        try printA.computeDistance(&distance, to: printB)
        return distance
    }
}

// MARK: - Future Core ML Face Embedding Matcher

final class CoreMLFaceEmbeddingMatcher: SceneIdentityMatching {
    let matcherIdentifier: String
    let defaultAcceptanceDistance: Float
    let defaultMarginDistance: Float
    
    private let model: any FaceEmbeddingModelProtocol
    
    init(model: any FaceEmbeddingModelProtocol) {
        self.matcherIdentifier = "coreml-\(model.modelVersion)"
        self.defaultAcceptanceDistance = model.acceptanceDistance
        self.defaultMarginDistance = model.marginDistance
        self.model = model
    }
    
    func computeFaceRepresentation(for croppedFace: CGImage) async throws -> SceneFaceRepresentation {
        let embedding = try await model.computeEmbedding(for: croppedFace)
        return .coreMLEmbedding(embedding)
    }
    
    func computeDistance(between query: SceneFaceRepresentation, reference: SceneFaceRepresentation) throws -> Float {
        guard case .coreMLEmbedding(let vecA) = query,
              case .coreMLEmbedding(let vecB) = reference else {
            throw SceneMatchingError.incompatibleRepresentations
        }
        let sim = cosineSimilarity(vecA, vecB)
        return max(0, 1.0 - sim)
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = (sqrt(normA) * sqrt(normB))
        return denom > 0 ? (dot / denom) : 0
    }
}
