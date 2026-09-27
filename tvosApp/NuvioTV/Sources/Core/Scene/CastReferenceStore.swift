import Foundation
import CoreGraphics
import Vision

struct CastReferenceFeature: @unchecked Sendable {
    let candidateId: String
    let name: String
    let character: String?
    let profileURL: URL?
    let representation: SceneFaceRepresentation
    let imageHash: String
    let matcherIdentifier: String
    
    init(
        candidateId: String,
        name: String,
        character: String?,
        profileURL: URL?,
        representation: SceneFaceRepresentation,
        imageHash: String,
        matcherIdentifier: String
    ) {
        self.candidateId = candidateId
        self.name = name
        self.character = character
        self.profileURL = profileURL
        self.representation = representation
        self.imageHash = imageHash
        self.matcherIdentifier = matcherIdentifier
    }
}

actor CastReferenceStore {
    private var referencesByCandidateId: [String: [CastReferenceFeature]] = [:]
    private var maxCandidates: Int = 100
    
    init(maxCandidates: Int = 100) {
        self.maxCandidates = maxCandidates
    }
    
    func store(features: [CastReferenceFeature], for candidateId: String) {
        if referencesByCandidateId.count >= maxCandidates {
            referencesByCandidateId.remove(at: referencesByCandidateId.startIndex)
        }
        var current = referencesByCandidateId[candidateId] ?? []
        for feature in features {
            if !current.contains(where: { $0.imageHash == feature.imageHash }) {
                current.append(feature)
            }
        }
        referencesByCandidateId[candidateId] = current
    }
    
    func features(for candidateId: String, matcherIdentifier: String) -> [CastReferenceFeature] {
        guard let list = referencesByCandidateId[candidateId] else { return [] }
        return list.filter { $0.matcherIdentifier == matcherIdentifier }
    }
    
    func allFeatures(matcherIdentifier: String) -> [CastReferenceFeature] {
        referencesByCandidateId.values.flatMap { $0 }.filter { $0.matcherIdentifier == matcherIdentifier }
    }
    
    func allFeaturesGrouped(matcherIdentifier: String) -> [String: [CastReferenceFeature]] {
        var result: [String: [CastReferenceFeature]] = [:]
        for (candidateId, list) in referencesByCandidateId {
            let filtered = list.filter { $0.matcherIdentifier == matcherIdentifier }
            if !filtered.isEmpty {
                result[candidateId] = filtered
            }
        }
        return result
    }
    
    func hasReferences(for candidateId: String, matcherIdentifier: String) -> Bool {
        guard let list = referencesByCandidateId[candidateId] else { return false }
        return list.contains { $0.matcherIdentifier == matcherIdentifier }
    }
    
    func store(embeddings: [CastReferenceFeature], for candidateId: String) {
        store(features: embeddings, for: candidateId)
    }
    
    func allEmbeddings(modelVersion: String) -> [CastReferenceFeature] {
        allFeatures(matcherIdentifier: "coreml-\(modelVersion)")
    }
    
    func clear() {
        referencesByCandidateId.removeAll()
    }
}

// MARK: - Compatibility Typealias and Extensions

typealias CastReferenceEmbedding = CastReferenceFeature

extension CastReferenceFeature {
    init(
        candidateId: String,
        name: String,
        character: String?,
        profileURL: URL?,
        embedding: [Float],
        imageHash: String,
        modelVersion: String
    ) {
        self.init(
            candidateId: candidateId,
            name: name,
            character: character,
            profileURL: profileURL,
            representation: .coreMLEmbedding(embedding),
            imageHash: imageHash,
            matcherIdentifier: "coreml-\(modelVersion)"
        )
    }
    
    var embedding: [Float] {
        if case .coreMLEmbedding(let vec) = representation {
            return vec
        }
        return []
    }
    
    var modelVersion: String {
        matcherIdentifier
    }
}
