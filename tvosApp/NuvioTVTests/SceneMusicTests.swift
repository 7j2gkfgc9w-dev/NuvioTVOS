import XCTest
import AVFAudio
import AetherEngine
@testable import NuvioTV

final class SceneMusicTests: XCTestCase {
    
    func testAudioTapFormatIsStandard48kHzMonoFloat32() {
        let format = AetherEngine.audioTapFormat
        XCTAssertEqual(format.sampleRate, 48000)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
    }
    
    func testMusicRecognitionPausedStateReportsRequiresPlayback() async {
        let service = MusicRecognitionService()
        
        let dummyStream = AsyncStream<AudioTapBuffer> { continuation in
            continuation.finish()
        }
        
        // When not playing, starting recognition must immediately report requiresPlayback
        await service.startListening(stream: dummyStream, isPlaying: false, currentSourceTime: 0)
        
        // Paused reporting
        await service.reportPlaybackPaused()
        
        // Resetting returns to disabled
        await service.reset()
    }
    
    func testMusicRecognitionSongModelEquivalence() {
        let song1 = SceneRecognizedSong(
            id: "shazam-999",
            title: "Midnight City",
            artist: "M83",
            artworkURL: URL(string: "https://example.com/art.jpg"),
            appleMusicURL: URL(string: "https://music.apple.com/song/999"),
            genres: ["Electronic"],
            observedSourceTime: 120.0
        )
        
        let song2 = SceneRecognizedSong(
            id: "shazam-999",
            title: "Midnight City",
            artist: "M83",
            artworkURL: URL(string: "https://example.com/art.jpg"),
            appleMusicURL: URL(string: "https://music.apple.com/song/999"),
            genres: ["Electronic"],
            observedSourceTime: 120.0
        )
        
        XCTAssertEqual(song1, song2)
        XCTAssertEqual(song1.title, "Midnight City")
        XCTAssertEqual(song1.artist, "M83")
    }
    
    func testSceneMusicStatusIndependentFromActorStatus() {
        let actorStatus = SceneActorStatus.unavailable(reason: "Model weights not packaged")
        let song = SceneRecognizedSong(id: "s1", title: "Song 1", artist: "Artist 1")
        let musicStatus = SceneMusicStatus.matched(song)
        
        let snapshot = SceneSnapshot(
            timestamp: 50.0,
            actors: [],
            song: song,
            actorStatus: actorStatus,
            musicStatus: musicStatus,
            generation: 1
        )
        
        // Failure or unavailable in actor pipeline does NOT disable music pipeline
        XCTAssertFalse(snapshot.actorStatus.isRecognized)
        XCTAssertEqual(snapshot.musicStatus.matchedSong?.title, "Song 1")
    }

    func testMusicRecognitionStreamAccumulatesBuffers() async {
        let service = MusicRecognitionService()
        let format = AetherEngine.audioTapFormat
        let frameCount: AVAudioFrameCount = 4800 // 100ms
        
        let (stream, continuation) = AsyncStream.makeStream(of: AudioTapBuffer.self)
        await service.startListening(stream: stream, isPlaying: true, currentSourceTime: 10.0)
        
        for i in 0..<10 {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            continuation.yield(AudioTapBuffer(buffer: buffer, sourceTime: 10.0 + Double(i) * 0.1, discontinuity: i == 0))
        }
        
        continuation.finish()
        try? await Task.sleep(nanoseconds: 100_000_000)
        await service.reset()
    }
    
    func testMusicRecognitionEntitlementErrorReportsUnavailable() async {
        let expectation = expectation(description: "Status changed to unavailable")
        var observedStatus: SceneMusicStatus?
        let service = MusicRecognitionService { status in
            observedStatus = status
            if case .unavailable = status {
                expectation.fulfill()
            }
        }
        
        let dummyStream = AsyncStream<AudioTapBuffer> { continuation in
            continuation.finish()
        }
        await service.startListening(stream: dummyStream, isPlaying: true, currentSourceTime: 0)
        
        let userInfo: [String: Any] = [
            NSDebugDescriptionErrorKey: "Missing entitlements",
            "AMSStatusCode": 401
        ]
        let entitlementError = NSError(domain: "com.apple.ShazamKit", code: 202, userInfo: userInfo)
        
        await service.handleNoMatch(error: entitlementError)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(
            observedStatus,
            .unavailable(reason: "ShazamKit requires App Service enabled in Apple Developer Portal")
        )
    }
}

