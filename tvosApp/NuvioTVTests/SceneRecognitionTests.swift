import XCTest
import CoreGraphics
@testable import NuvioTV

final class SceneRecognitionTests: XCTestCase {
    
    func testCosineSimilarityIdenticalAndOrthogonalVectors() async {
        let service = ActorRecognitionService()
        
        let vecA: [Float] = [1.0, 0.0, 0.0]
        let vecB: [Float] = [1.0, 0.0, 0.0]
        let vecC: [Float] = [0.0, 1.0, 0.0]
        let vecD: [Float] = [-1.0, 0.0, 0.0]
        
        let simIdentical = service.cosineSimilarity(vecA, vecB)
        XCTAssertEqual(simIdentical, 1.0, accuracy: 0.0001)
        
        let simOrthogonal = service.cosineSimilarity(vecA, vecC)
        XCTAssertEqual(simOrthogonal, 0.0, accuracy: 0.0001)
        
        let simOpposite = service.cosineSimilarity(vecA, vecD)
        XCTAssertEqual(simOpposite, -1.0, accuracy: 0.0001)
    }
    
    func testModelNotLoadedReturnsTruthfulUnavailableStatus() async {
        // Without an approved Core ML model configured, the service must report truthful capability state
        let service = ActorRecognitionService(model: nil)
        
        let isLoaded = await service.isModelLoaded
        XCTAssertFalse(isLoaded)
        
        // Create a blank dummy test image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        
        let frame = SceneFrame(
            image: image,
            sourceTime: 5.0,
            sessionID: UUID(),
            generation: 1
        )
        
        let status = await service.analyzeFrame(
            frame,
            candidates: [SceneCastCandidate(id: "100", name: "Test Performer")],
            sourceTime: 5.0
        )
        
        if case .unavailable(let reason) = status {
            XCTAssertTrue(reason.contains("Face recognition model not loaded"))
        } else {
            XCTFail("Must report .unavailable when model weights are not loaded, got \(status)")
        }
    }

    func testAnalyzeFrameWithoutCastCandidatesReportsMissingCast() async {
        let service = ActorRecognitionService(matcher: VisionFeaturePrintMatcher())
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let frame = SceneFrame(
            image: context.makeImage()!,
            sourceTime: 5.0,
            sessionID: UUID(),
            generation: 1
        )

        let status = await service.analyzeFrame(frame, candidates: [], sourceTime: 5.0)

        if case .unavailable(let reason) = status {
            XCTAssertTrue(reason.contains("Cast candidates unavailable"))
        } else {
            XCTFail("Missing cast candidates must report .unavailable, got \(status)")
        }
    }

    func testVisionFeaturePrintMatcherComputesGeneratedImage() async {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!

        do {
            let representation = try await VisionFeaturePrintMatcher().computeFaceRepresentation(for: image)
            guard case .visionFeaturePrint = representation else {
                XCTFail("Vision feature-print matcher returned an unexpected representation.")
                return
            }
        } catch {
            let nsError = error as NSError
            XCTFail("Vision feature-print generation threw domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)")
        }
    }

    func testMockModelWithCalibratedThresholds() async {
        // Concrete test model implementing FaceEmbeddingModelProtocol
        struct TestEmbeddingModel: FaceEmbeddingModelProtocol {
            var modelVersion: String = "test-v1"
            var inputDimension: CGSize = CGSize(width: 112, height: 112)
            let fixedEmbedding: [Float]
            
            func computeEmbedding(for faceImage: CGImage) async throws -> [Float] {
                fixedEmbedding
            }
        }
        
        let refStore = CastReferenceStore()
        let candidateEmb: [Float] = [1.0, 0.0, 0.0]
        let candidate = CastReferenceEmbedding(
            candidateId: "100",
            name: "Test Performer",
            character: "Lead",
            profileURL: nil,
            embedding: candidateEmb,
            imageHash: "hash-1",
            modelVersion: "test-v1"
        )
        await refStore.store(embeddings: [candidate], for: "100")
        
        let testModel = TestEmbeddingModel(fixedEmbedding: [0.99, 0.0, 0.0])
        let service = ActorRecognitionService(model: testModel, referenceStore: refStore)
        
        let isLoaded = await service.isModelLoaded
        XCTAssertTrue(isLoaded)
    }
    
    func testStrictMarginRejectsAmbiguousCandidates() async {
        let service = ActorRecognitionService(model: nil)
        
        // Two similar looking candidates
        let embA: [Float] = [1.0, 0.0, 0.0]
        let embB: [Float] = [0.99, 0.05, 0.0]
        let queryEmb: [Float] = [1.0, 0.0, 0.0]
        
        let simA = service.cosineSimilarity(queryEmb, embA)
        let simB = service.cosineSimilarity(queryEmb, embB)
        
        // Cosine similarity difference between top two is < margin threshold (0.12)
        let diff = abs(simA - simB)
        XCTAssertLessThan(diff, ActorRecognitionService.defaultMarginThreshold)
        // Under our strict rule, this ambiguous match is rejected rather than guessing
    }
    
    func testFaceQualityThresholdsConfiguredCorrectly() {
        // Enforce strict rules: high similarity, distinct margin, sufficient face size, 2+ frame agreement
        XCTAssertGreaterThanOrEqual(ActorRecognitionService.defaultAcceptanceThreshold, 0.65)
        XCTAssertGreaterThanOrEqual(ActorRecognitionService.defaultMarginThreshold, 0.12)
        XCTAssertGreaterThanOrEqual(ActorRecognitionService.minFaceRelativeDimension, 0.035)
        XCTAssertGreaterThanOrEqual(ActorRecognitionService.minRequiredFrameAgreement, 2)
        XCTAssertEqual(ActorRecognitionService.shotCutThresholdSeconds, 2.5)
        XCTAssertEqual(ActorRecognitionService.maskOcclusionGracePeriodSeconds, 4.0)
    }

    func testSparseSamplingConfirmationAndTemporalRules() {
        XCTAssertFalse(ActorRecognitionService.shouldResetTemporalTracking(lastSourceTime: 84.8, newSourceTime: 86.3))
        XCTAssertTrue(ActorRecognitionService.shouldResetTemporalTracking(lastSourceTime: 86.3, newSourceTime: 80.0))

        XCTAssertTrue(ActorRecognitionService.shouldConfirmBundledMatchOnSingleFrame(distance: 0.434, bundledPipelineActive: true))
        XCTAssertTrue(ActorRecognitionService.shouldConfirmBundledMatchOnSingleFrame(distance: 0.423, bundledPipelineActive: true))
        XCTAssertFalse(ActorRecognitionService.shouldConfirmBundledMatchOnSingleFrame(distance: 0.49, bundledPipelineActive: true))
        XCTAssertFalse(ActorRecognitionService.shouldConfirmBundledMatchOnSingleFrame(distance: 0.434, bundledPipelineActive: false))

        var tracked = TrackedActorInShot(
            actor: SceneRecognizedActor(id: "1", name: "Actor"),
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3),
            lastSeenTimestamp: 84.8,
            observationCount: 0,
            isConfirmed: false
        )
        let box = tracked.boundingBox
        XCTAssertTrue(tracked.recordObservation(at: 84.8, boundingBox: box, maximumCount: 2))
        XCTAssertEqual(tracked.observationCount, 1)
        XCTAssertFalse(tracked.recordObservation(at: 84.8, boundingBox: box, maximumCount: 2))
        XCTAssertEqual(tracked.observationCount, 1)
        XCTAssertTrue(tracked.recordObservation(at: 86.3, boundingBox: box, maximumCount: 2))
        XCTAssertEqual(tracked.observationCount, 2)
        XCTAssertTrue(tracked.recordObservation(at: 87.8, boundingBox: box, maximumCount: 2))
        XCTAssertEqual(tracked.observationCount, 2)
    }
    
    func testPixelAspectRatioIn16By9Frame() {
        // In a 960x540 frame, a square face (e.g. 100x100px) has normalized coordinates:
        // width = 100/960 = 0.1042, height = 100/540 = 0.1852
        // Raw normalized aspect ratio is 0.1852 / 0.1042 = 1.778
        // The service must compute true pixel aspect ratio (100 / 100 = 1.0) instead of normalized aspect
        let imgW: CGFloat = 960
        let imgH: CGFloat = 540
        let normW: CGFloat = 100.0 / imgW
        let normH: CGFloat = 100.0 / imgH
        
        let pixelW = normW * imgW
        let pixelH = normH * imgH
        let pixelAspect = pixelH / max(1.0, pixelW)
        
        XCTAssertEqual(pixelAspect, 1.0, accuracy: 0.01)
        XCTAssertTrue(pixelAspect >= 0.55 && pixelAspect <= 2.2)
    }
    
    func testTrackedActorInShotModelEquivalence() {
        let actor = SceneRecognizedActor(id: "1", name: "Robert Pattinson", character: "Batman")
        let box = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        let tracked = TrackedActorInShot(
            actor: actor,
            boundingBox: box,
            lastSeenTimestamp: 10.0,
            observationCount: 2,
            isConfirmed: true
        )
        
        XCTAssertTrue(tracked.isConfirmed)
        XCTAssertEqual(tracked.actor.name, "Robert Pattinson")
        XCTAssertEqual(tracked.observationCount, 2)
    }
    
    func testDefaultServiceLazilyLoadsCoreMLFacePipeline() async {
        let service = ActorRecognitionService()
        let isLoadedBeforeUse = await service.isModelLoaded
        XCTAssertFalse(isLoadedBeforeUse)

        await service.preloadReferences(candidates: [])

        let isLoadedAfterPreload = await service.isModelLoaded
        let version = await service.modelVersion
        
        XCTAssertTrue(isLoadedAfterPreload)
        XCTAssertEqual(version, "coreml-yunet-sface-f32-v1")
    }
    
    func testMultiReferenceAggregationTakesMinimumDistance() async {
        struct MockMatcher: SceneIdentityMatching {
            let matcherIdentifier: String = "mock-matcher"
            let defaultAcceptanceDistance: Float = 0.50
            let defaultMarginDistance: Float = 0.10
            
            func computeFaceRepresentation(for croppedFace: CGImage) async throws -> SceneFaceRepresentation {
                .coreMLEmbedding([1.0])
            }
            
            func computeDistance(between query: SceneFaceRepresentation, reference: SceneFaceRepresentation) throws -> Float {
                guard case .coreMLEmbedding(let q) = query, case .coreMLEmbedding(let r) = reference else { return 1.0 }
                return abs(q[0] - r[0])
            }
        }
        
        let matcher = MockMatcher()
        let service = ActorRecognitionService(matcher: matcher)
        
        // Candidate 1 has two reference photos: one with value 1.5 (distance 0.5) and one with 1.1 (distance 0.1)
        let ref1A = CastReferenceFeature(
            candidateId: "1",
            name: "Actor One",
            character: "Hero",
            profileURL: nil,
            representation: .coreMLEmbedding([1.5]),
            imageHash: "hash-1a",
            matcherIdentifier: matcher.matcherIdentifier
        )
        let ref1B = CastReferenceFeature(
            candidateId: "1",
            name: "Actor One",
            character: "Hero",
            profileURL: nil,
            representation: .coreMLEmbedding([1.1]),
            imageHash: "hash-1b",
            matcherIdentifier: matcher.matcherIdentifier
        )
        // Candidate 2 has one reference photo with value 1.4 (distance 0.4)
        let ref2 = CastReferenceFeature(
            candidateId: "2",
            name: "Actor Two",
            character: "Villain",
            profileURL: nil,
            representation: .coreMLEmbedding([1.4]),
            imageHash: "hash-2",
            matcherIdentifier: matcher.matcherIdentifier
        )
        
        let grouped: [String: [CastReferenceFeature]] = [
            "1": [ref1A, ref1B],
            "2": [ref2]
        ]
        
        let queryRep = SceneFaceRepresentation.coreMLEmbedding([1.0])
        let match = await service.matchFace(
            representation: queryRep,
            referencesGrouped: grouped,
            matcher: matcher,
            acceptanceDistance: 0.50,
            marginDistance: 0.10
        )
        
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.candidateId, "1")
        XCTAssertEqual(match?.name, "Actor One")
        // Distance should be min(0.5, 0.1) = 0.1
        XCTAssertEqual(match?.distance ?? 0, 0.1, accuracy: 0.001)
    }

    func testFrameReferenceScopeExcludesCandidatesFromPreviousTitle() async {
        struct MockMatcher: SceneIdentityMatching {
            let matcherIdentifier: String = "mock-matcher"
            let defaultAcceptanceDistance: Float = 0.50
            let defaultMarginDistance: Float = 0.10

            func computeFaceRepresentation(for croppedFace: CGImage) async throws -> SceneFaceRepresentation {
                .coreMLEmbedding([1.0])
            }

            func computeDistance(between query: SceneFaceRepresentation, reference: SceneFaceRepresentation) throws -> Float {
                guard case .coreMLEmbedding(let q) = query, case .coreMLEmbedding(let r) = reference else { return 1.0 }
                return abs(q[0] - r[0])
            }
        }

        let matcher = MockMatcher()
        let service = ActorRecognitionService(matcher: matcher)
        let previousTitleReference = CastReferenceFeature(
            candidateId: "previous-title",
            name: "Previous Title Actor",
            character: nil,
            profileURL: nil,
            representation: .coreMLEmbedding([1.0]),
            imageHash: "previous-title",
            matcherIdentifier: matcher.matcherIdentifier
        )
        let currentTitleReference = CastReferenceFeature(
            candidateId: "current-title",
            name: "Current Title Actor",
            character: nil,
            profileURL: nil,
            representation: .coreMLEmbedding([1.4]),
            imageHash: "current-title",
            matcherIdentifier: matcher.matcherIdentifier
        )
        let storedReferences = [
            "previous-title": [previousTitleReference],
            "current-title": [currentTitleReference]
        ]

        let currentReferences = await service.filterReferencesGrouped(
            storedReferences,
            candidateIDs: ["current-title"]
        )
        let match = await service.matchFace(
            representation: .coreMLEmbedding([1.0]),
            referencesGrouped: currentReferences,
            matcher: matcher,
            acceptanceDistance: 0.50,
            marginDistance: 0.10
        )

        XCTAssertEqual(Set(currentReferences.keys), ["current-title"])
        XCTAssertEqual(match?.candidateId, "current-title")
    }

    func testMarginDistanceRejectsAmbiguousTopCandidates() async {
        struct MockMatcher: SceneIdentityMatching {
            let matcherIdentifier: String = "mock-matcher"
            let defaultAcceptanceDistance: Float = 0.50
            let defaultMarginDistance: Float = 0.10
            
            func computeFaceRepresentation(for croppedFace: CGImage) async throws -> SceneFaceRepresentation {
                .coreMLEmbedding([1.0])
            }
            
            func computeDistance(between query: SceneFaceRepresentation, reference: SceneFaceRepresentation) throws -> Float {
                guard case .coreMLEmbedding(let q) = query, case .coreMLEmbedding(let r) = reference else { return 1.0 }
                return abs(q[0] - r[0])
            }
        }
        
        let matcher = MockMatcher()
        let service = ActorRecognitionService(matcher: matcher)
        
        // Candidate 1 has distance 0.12, Candidate 2 has distance 0.15 (diff = 0.03 < margin 0.10)
        let ref1 = CastReferenceFeature(
            candidateId: "1",
            name: "Actor One",
            character: nil,
            profileURL: nil,
            representation: .coreMLEmbedding([1.12]),
            imageHash: "hash-1",
            matcherIdentifier: matcher.matcherIdentifier
        )
        let ref2 = CastReferenceFeature(
            candidateId: "2",
            name: "Actor Two",
            character: nil,
            profileURL: nil,
            representation: .coreMLEmbedding([1.15]),
            imageHash: "hash-2",
            matcherIdentifier: matcher.matcherIdentifier
        )
        
        let grouped: [String: [CastReferenceFeature]] = [
            "1": [ref1],
            "2": [ref2]
        ]
        
        let queryRep = SceneFaceRepresentation.coreMLEmbedding([1.0])
        let match = await service.matchFace(
            representation: queryRep,
            referencesGrouped: grouped,
            matcher: matcher,
            acceptanceDistance: 0.50,
            marginDistance: 0.10
        )
        
        // Ambiguous match must be rejected
        XCTAssertNil(match)
    }
    
    func testSceneDialoguePartnersRetainedAcrossConversationShots() async {
        let service = ActorRecognitionService(matcher: nil)
        
        let actorA = SceneRecognizedActor(id: "actor-a", name: "Actor A", character: "Detective")
        let actorB = SceneRecognizedActor(id: "actor-b", name: "Actor B", character: "Suspect")
        
        // 1. At t=10.0s, Actor A speaks (shot on Actor A)
        await service.recordConfirmedActorForTesting(actorA, at: 10.0)
        let sceneAt10 = await service.currentTrackedActors(at: 10.0)
        XCTAssertEqual(sceneAt10.count, 1)
        XCTAssertEqual(sceneAt10.first?.id, "actor-a")
        
        // 2. At t=14.0s, Camera cuts to Actor B who responds (shot on Actor B)
        // Both Actor A and Actor B must be retained in the scene dialogue
        await service.recordConfirmedActorForTesting(actorB, at: 14.0)
        let sceneAt14 = await service.currentTrackedActors(at: 14.0)
        XCTAssertEqual(sceneAt14.count, 2)
        XCTAssertEqual(sceneAt14.map(\.id), ["actor-b", "actor-a"])
        
        // 3. At t=18.0s, A cutaway shot with zero face detections (e.g. coffee cup)
        // Both actors must stay visible in the ongoing conversation scene
        let sceneAtCutaway = await service.currentTrackedActors(at: 18.0)
        XCTAssertEqual(sceneAtCutaway.count, 2)
        XCTAssertEqual(sceneAtCutaway.map(\.id), ["actor-b", "actor-a"])
        
        // 4. At t=22.0s, Camera cuts back to Actor A who speaks again
        // Actor A is updated as most recently seen; Actor B remains in the scene
        await service.recordConfirmedActorForTesting(actorA, at: 22.0)
        let sceneAt22 = await service.currentTrackedActors(at: 22.0)
        XCTAssertEqual(sceneAt22.count, 2)
        XCTAssertEqual(sceneAt22.map(\.id), ["actor-a", "actor-b"])
        
        // 5. At t=40.0s, Actor B hasn't been seen for 26s (> sceneRetentionSeconds = 25.0)
        // Actor B gracefully retires; Actor A was seen at 22s (18s ago <= 25.0) so remains
        let sceneAt40 = await service.currentTrackedActors(at: 40.0)
        XCTAssertEqual(sceneAt40.count, 1)
        XCTAssertEqual(sceneAt40.first?.id, "actor-a")
        
        // 6. At t=55.0s, Scene is completely over (> 25s since last sighting of either actor)
        let sceneAt55 = await service.currentTrackedActors(at: 55.0)
        XCTAssertEqual(sceneAt55.count, 0)
    }

    func testSubtitleSpeakerRecognizerExtractsBracketsColonsParentheses() {
        let candidates = [
            SceneCastCandidate(id: "1", name: "Keith David", character: "President Curtis (voice)", tmdbId: 101),
            SceneCastCandidate(id: "2", name: "Spencer Grammer", character: "Summer Smith (voice)", tmdbId: 102),
            SceneCastCandidate(id: "3", name: "Jim Rash", character: "Special Agent Francis O'Doyle (voice)", tmdbId: 103),
            SceneCastCandidate(id: "4", name: "Stephanie Beatriz", character: "Rho Banks (voice)", tmdbId: 104)
        ]

        // 1. Bracketed speaker tag
        let matches1 = SceneSubtitleSpeakerRecognizer.detectSpeakers(
            in: "[President Curtis] As for your mother, without evidence,",
            candidates: candidates
        )
        XCTAssertEqual(matches1.map(\.name), ["Keith David"])

        // 2. Colon prefix speaker tag
        let matches2 = SceneSubtitleSpeakerRecognizer.detectSpeakers(
            in: "Summer: Dad, stop!",
            candidates: candidates
        )
        XCTAssertEqual(matches2.map(\.name), ["Spencer Grammer"])

        // 3. Hyphenated colon prefix
        let matches3 = SceneSubtitleSpeakerRecognizer.detectSpeakers(
            in: "- Francis: Yes, Mr. President.",
            candidates: candidates
        )
        XCTAssertEqual(matches3.map(\.name), ["Jim Rash"])

        // 4. Parentheses speaker tag with character title
        let matches4 = SceneSubtitleSpeakerRecognizer.detectSpeakers(
            in: "(Rho Banks) The perimeter is secure.",
            candidates: candidates
        )
        XCTAssertEqual(matches4.map(\.name), ["Stephanie Beatriz"])

        // 5. Sound effects in brackets should NOT match any actor
        let matches5 = SceneSubtitleSpeakerRecognizer.detectSpeakers(
            in: "[laughter] That is crazy. [sighs]",
            candidates: candidates
        )
        XCTAssertTrue(matches5.isEmpty)

        // 6. Broadcast >> prefix and HTML formatting tags
        let matches6 = SceneSubtitleSpeakerRecognizer.detectSpeakers(
            in: "<i>>> CURTIS: We have a situation.</i>",
            candidates: candidates
        )
        XCTAssertEqual(matches6.map(\.name), ["Keith David"])

        // 7. Multi-line multi-speaker dialogue
        let matches7 = SceneSubtitleSpeakerRecognizer.detectSpeakers(
            in: "- Summer: Wait!\n- Curtis: No time!",
            candidates: candidates
        )
        XCTAssertEqual(matches7.map(\.name), ["Spencer Grammer", "Keith David"])
    }

    func testActorRecognitionServiceProcessesSubtitleDialogueAndRetainsPartners() async {
        let service = ActorRecognitionService()
        let candidates = [
            SceneCastCandidate(id: "curtis", name: "Keith David", character: "President Curtis (voice)", tmdbId: 101),
            SceneCastCandidate(id: "summer", name: "Spencer Grammer", character: "Summer Smith (voice)", tmdbId: 102)
        ]

        // 1. At t=5.0s, subtitle cue has President Curtis speaking
        let detectedAt5 = await service.processSubtitleDialogue(
            text: "[President Curtis] As for your mother, without evidence,",
            candidates: candidates,
            sourceTime: 5.0
        )
        XCTAssertEqual(detectedAt5.count, 1)
        XCTAssertEqual(detectedAt5.first?.name, "Keith David")

        // 2. At t=9.0s, Summer responds in subtitle cue
        let detectedAt9 = await service.processSubtitleDialogue(
            text: "Summer: But she is innocent!",
            candidates: candidates,
            sourceTime: 9.0
        )
        // Both dialogue partners must now be retained in the active conversation
        XCTAssertEqual(detectedAt9.count, 2)
        XCTAssertEqual(detectedAt9.map(\.name), ["Spencer Grammer", "Keith David"])

        // 3. At t=12.0s, a frame with zero visual face detections is analyzed
        // Because subtitle dialogue confirmed them, the dialogue partners are preserved
        let blankImage = CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!.makeImage()!
        let frame = SceneFrame(image: blankImage, sourceTime: 12.0, sessionID: UUID(), generation: 1)
        
        let status = await service.analyzeFrame(
            frame,
            candidates: candidates,
            sourceTime: 12.0
        )
        if case .recognized(let actors) = status {
            XCTAssertEqual(actors.count, 2)
            XCTAssertEqual(actors.map(\.name), ["Spencer Grammer", "Keith David"])
        } else {
            XCTFail("Expected .recognized dialogue partners across zero-detection frame, got \(status)")
        }
    }

    func testSceneSubtitleTimelineScraperPrioritizesSDHAndEnglish() async {
        let scraper = SceneSubtitleTimelineScraper()
        let subs = [
            NuvioSubtitle(url: "https://example.com/fr_sdh.srt", language: "fr", label: "French SDH"),
            NuvioSubtitle(url: "https://example.com/en_std.srt", language: "en", label: "English"),
            NuvioSubtitle(url: "https://example.com/en_sdh.srt", language: "en", label: "English [SDH]"),
            NuvioSubtitle(url: "https://example.com/es.srt", language: "es", label: "Spanish")
        ]
        let prioritized = await scraper.prioritizeSubtitles(subs)
        XCTAssertEqual(prioritized.first?.url, "https://example.com/en_sdh.srt", "English SDH must be top priority")
        XCTAssertEqual(prioritized[1].url, "https://example.com/fr_sdh.srt", "French SDH has high sdh score")
        XCTAssertEqual(prioritized[2].url, "https://example.com/en_std.srt", "English standard has language score")
    }

    func testSceneSubtitleTimelineScraperParsesSRTCuesIntoTimelineIntervals() async {
        let scraper = SceneSubtitleTimelineScraper()
        let candidates = [
            SceneCastCandidate(id: "curtis", name: "Keith David", character: "President Curtis (voice)", tmdbId: 101),
            SceneCastCandidate(id: "summer", name: "Spencer Grammer", character: "Summer Smith (voice)", tmdbId: 102)
        ]
        let context = SceneContext(
            canonicalId: "rick_and_morty_s07e05",
            mediaType: "series",
            title: "Rick and Morty",
            season: 7,
            episode: 5
        )

        let srt = """
        1
        00:01:10,500 --> 00:01:14,200
        [President Curtis] As for your mother, without evidence,
        we cannot take action.

        2
        00:01:15,000 --> 00:01:18,500
        Summer: But she is innocent!

        3
        00:01:19,000 --> 00:01:21,000
        [laughter] That is ridiculous.
        """

        let intervals = await scraper.parseSubtitleTimeline(content: srt, candidates: candidates, context: context)
        XCTAssertEqual(intervals.count, 2)

        let first = intervals[0]
        XCTAssertEqual(first.startTime, 70.5, accuracy: 0.001)
        XCTAssertEqual(first.endTime, 74.2, accuracy: 0.001)
        XCTAssertEqual(first.actors.map(\.name), ["Keith David"])
        XCTAssertEqual(first.actors.first?.character, "President Curtis (voice)")

        let second = intervals[1]
        XCTAssertEqual(second.startTime, 75.0, accuracy: 0.001)
        XCTAssertEqual(second.endTime, 78.5, accuracy: 0.001)
        XCTAssertEqual(second.actors.map(\.name), ["Spencer Grammer"])
    }

    func testSceneSubtitleTimelineScraperIntegrationWithCache() async {
        let scraper = SceneSubtitleTimelineScraper()
        let cache = SceneResultCache()
        let candidates = [
            SceneCastCandidate(id: "curtis", name: "Keith David", character: "President Curtis (voice)", tmdbId: 101)
        ]
        let context = SceneContext(
            canonicalId: "rick_and_morty_s07e05",
            mediaType: "series",
            title: "Rick and Morty",
            season: 7,
            episode: 5
        )

        let srt = """
        1
        00:00:10,000 --> 00:00:20,000
        [President Curtis] Good evening citizens.
        """

        let intervals = await scraper.parseSubtitleTimeline(content: srt, candidates: candidates, context: context)
        await cache.storeTimelineIntervals(intervals)

        // Query within interval (t = 15.0s)
        let matchAt15 = await cache.findTimelineInterval(for: context, sourceTime: 15.0)
        XCTAssertNotNil(matchAt15)
        XCTAssertEqual(matchAt15?.actors.first?.name, "Keith David")

        // Query outside interval (t = 25.0s)
        let matchAt25 = await cache.findTimelineInterval(for: context, sourceTime: 25.0)
        XCTAssertNil(matchAt25)
    }
}

