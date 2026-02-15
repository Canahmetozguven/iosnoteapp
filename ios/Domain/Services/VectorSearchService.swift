import Foundation

/// Pure Swift service for vector similarity search.
/// No external dependencies - operates on data passed in.
///
/// Mathematical Foundation:
/// ========================
/// Cosine Similarity measures the cosine of the angle between two vectors.
/// It ranges from -1 (opposite) to 1 (identical), with 0 being orthogonal.
///
/// Formula: cos(θ) = (A · B) / (‖A‖ × ‖B‖)
///
/// Where:
///   A · B  = Dot product = Σ(Aᵢ × Bᵢ)
///   ‖A‖    = L2 norm = √(Σ(Aᵢ²))
///
/// If vectors are pre-normalized (‖A‖ = ‖B‖ = 1), similarity = dot product.
/// This implementation normalizes anyway for safety.
class VectorSearchService {
    
    init() {}
    
    /// Finds the most similar notes to a query embedding.
    ///
    /// - Parameters:
    ///   - queryEmbedding: The embedding vector to search against
    ///   - notes: Array of notes to search (with optional embeddings)
    ///   - topK: Maximum number of results to return
    ///
    /// - Returns: Top K notes sorted by descending similarity score
    func findSimilarNotes(
        queryEmbedding: [Float],
        notes: [Note],
        topK: Int
    ) -> [Note] {
        // Guard against empty inputs
        guard !queryEmbedding.isEmpty, !notes.isEmpty, topK > 0 else {
            return []
        }
        
        // Pre-compute query norm once (avoid recalculating per note)
        let queryNorm = l2Norm(queryEmbedding)
        guard queryNorm > 0 else {
            // Zero vector has no direction - can't compute similarity
            return []
        }
        
        // Calculate similarity for notes that have embeddings
        let scoredNotes: [(note: Note, score: Float)] = notes.compactMap { note in
            guard let noteEmbedding = note.embedding,
                  !noteEmbedding.isEmpty,
                  noteEmbedding.count == queryEmbedding.count else {
                // Skip notes without embeddings or dimension mismatch
                return nil
            }
            
            let score = cosineSimilarity(
                v1: queryEmbedding,
                v1Norm: queryNorm,
                v2: noteEmbedding
            )
            return (note: note, score: score)
        }
        
        // Sort by descending similarity and take top K
        let topNotes = scoredNotes
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0.note }
        
        return Array(topNotes)
    }
    
    // MARK: - Vector Math
    
    /// Calculates cosine similarity between two vectors.
    ///
    /// Cosine Similarity = dot(A, B) / (norm(A) × norm(B))
    ///
    /// - Parameters:
    ///   - v1: First vector
    ///   - v1Norm: Pre-computed L2 norm of v1 (optimization)
    ///   - v2: Second vector
    ///
    /// - Returns: Similarity score in range [-1, 1]. Higher = more similar.
    private func cosineSimilarity(
        v1: [Float],
        v1Norm: Float,
        v2: [Float]
    ) -> Float {
        let v2Norm = l2Norm(v2)
        
        // Handle degenerate case (zero vector)
        guard v2Norm > 0 else {
            return 0.0
        }
        
        let dot = dotProduct(v1, v2)
        
        // cos(θ) = (A · B) / (‖A‖ × ‖B‖)
        return dot / (v1Norm * v2Norm)
    }
    
    /// Computes dot product (inner product) of two vectors.
    ///
    /// Dot Product = Σ(Aᵢ × Bᵢ) for i in 0..<n
    ///
    /// Note: Using simple loop for clarity. For large vectors,
    /// vDSP.dot from Accelerate framework would be faster.
    ///
    /// - Returns: Scalar dot product value
    private func dotProduct(_ v1: [Float], _ v2: [Float]) -> Float {
        // Assumes same length (caller verified)
        var result: Float = 0.0
        for i in 0..<v1.count {
            result += v1[i] * v2[i]
        }
        return result
    }
    
    /// Computes L2 (Euclidean) norm of a vector.
    ///
    /// L2 Norm = √(Σ(Aᵢ²)) = √(A · A)
    ///
    /// The L2 norm gives the "length" or "magnitude" of the vector.
    ///
    /// - Returns: Non-negative scalar norm value
    private func l2Norm(_ v: [Float]) -> Float {
        var sumOfSquares: Float = 0.0
        for value in v {
            sumOfSquares += value * value
        }
        return sqrtf(sumOfSquares)
    }
}
