import CoreML
import XCTest
@testable import NuvioTV

final class SceneCoreMLFacePipelineTests: XCTestCase {
    func testYuNetAndSFaceRunOnCPU() throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly

        let yuNetURL = try XCTUnwrap(
            Bundle.main.url(forResource: "YuNet", withExtension: "mlmodelc", subdirectory: "SceneModels")
                ?? Bundle.main.url(forResource: "YuNet", withExtension: "mlmodelc")
        )
        let yuNet = try MLModel(contentsOf: yuNetURL, configuration: configuration)
        let yuNetInput = try MLMultiArray(shape: [1, 3, 640, 640].map(NSNumber.init(value:)), dataType: .float32)
        let yuNetProvider = try MLDictionaryFeatureProvider(dictionary: ["frame_input": yuNetInput])
        let yuNetOutput = try yuNet.prediction(from: yuNetProvider)
        XCTAssertEqual(yuNetOutput.featureValue(for: "var_762")?.multiArrayValue?.shape.map(\.intValue), [1, 6400, 1])

        let sFaceURL = try XCTUnwrap(
            Bundle.main.url(forResource: "SFace", withExtension: "mlmodelc", subdirectory: "SceneModels")
                ?? Bundle.main.url(forResource: "SFace", withExtension: "mlmodelc")
        )
        let sFace = try MLModel(contentsOf: sFaceURL, configuration: configuration)
        let sFaceInput = try MLMultiArray(shape: [1, 3, 112, 112].map(NSNumber.init(value:)), dataType: .float32)
        let sFaceProvider = try MLDictionaryFeatureProvider(dictionary: ["face_input": sFaceInput])
        let sFaceOutput = try sFace.prediction(from: sFaceProvider)
        XCTAssertEqual(sFaceOutput.featureValue(for: "var_811")?.multiArrayValue?.shape.map(\.intValue), [1, 128])
    }

    func testSFaceProducesNormalizedDistinctEmbeddings() async throws {
        let pipeline = try SceneCoreMLFacePipeline(bundle: .main)
        XCTAssertEqual(pipeline.modelVersion, "yunet-sface-f32-v1")
        XCTAssertEqual(pipeline.inputDimension, CGSize(width: 112, height: 112))

        let faceLikeImage = makeSyntheticImage { context in
            context.setFillColor(CGColor(gray: 0.88, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 112, height: 112))
            context.setFillColor(CGColor(gray: 0.08, alpha: 1))
            context.fillEllipse(in: CGRect(x: 32, y: 46, width: 13, height: 10))
            context.fillEllipse(in: CGRect(x: 67, y: 46, width: 13, height: 10))
            context.fillEllipse(in: CGRect(x: 51, y: 64, width: 11, height: 16))
            context.fillEllipse(in: CGRect(x: 40, y: 84, width: 33, height: 7))
        }
        let checkerboardImage = makeSyntheticImage { context in
            context.setFillColor(CGColor(gray: 0.95, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 112, height: 112))
            context.setFillColor(CGColor(gray: 0.05, alpha: 1))
            for row in 0..<14 {
                for column in 0..<14 where (row + column).isMultiple(of: 2) {
                    context.fill(CGRect(x: CGFloat(column * 8), y: CGFloat(row * 8), width: 8, height: 8))
                }
            }
        }
        let landmarks = [
            CGPoint(x: 38.2946, y: 51.6963),
            CGPoint(x: 73.5318, y: 51.5014),
            CGPoint(x: 56.0252, y: 71.7366),
            CGPoint(x: 41.5493, y: 92.3655),
            CGPoint(x: 70.7299, y: 92.2041)
        ]

        let faceEmbedding = try await pipeline.embedding(for: faceLikeImage, landmarks: landmarks)
        let checkerboardEmbedding = try await pipeline.embedding(for: checkerboardImage, landmarks: landmarks)
        let faceNorm = sqrt(faceEmbedding.reduce(Float.zero) { $0 + $1 * $1 })
        let checkerboardNorm = sqrt(checkerboardEmbedding.reduce(Float.zero) { $0 + $1 * $1 })
        let distance = sqrt(zip(faceEmbedding, checkerboardEmbedding).reduce(Float.zero) { partial, pair in
            let difference = pair.0 - pair.1
            return partial + difference * difference
        })

        XCTAssertEqual(faceEmbedding.count, 128)
        XCTAssertEqual(checkerboardEmbedding.count, 128)
        XCTAssertTrue(faceEmbedding.allSatisfy(\.isFinite))
        XCTAssertTrue(checkerboardEmbedding.allSatisfy(\.isFinite))
        XCTAssertEqual(faceNorm, 1, accuracy: 0.001)
        XCTAssertEqual(checkerboardNorm, 1, accuracy: 0.001)
        print("[SceneCoreMLFacePipelineTests] synthetic SFace embedding L2 distance=\(String(format: "%.9f", distance))")
        XCTAssertGreaterThan(distance, 0.001)
    }

    private func makeSyntheticImage(drawing: (CGContext) -> Void) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 112,
            height: 112,
            bitsPerComponent: 8,
            bytesPerRow: 112 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.translateBy(x: 0, y: 112)
        context.scaleBy(x: 1, y: -1)
        drawing(context)
        return context.makeImage()!
    }
}
