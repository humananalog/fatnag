import Foundation
import llama

enum LlamaMetalEngineError: Error, LocalizedError {
    case couldNotLoadModel
    case couldNotCreateContext
    case decodeFailed
    case emptyPrompt

    var errorDescription: String? {
        switch self {
        case .couldNotLoadModel: return "Could not load on-device polish model."
        case .couldNotCreateContext: return "Could not create Metal context."
        case .decodeFailed: return "On-device polish decode failed."
        case .emptyPrompt: return "Empty polish prompt."
        }
    }
}

/// Thin Metal-backed llama.cpp session for short polish prompts.
final class LlamaMetalEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampling: UnsafeMutablePointer<llama_sampler>?
    private var batch: llama_batch?
    private var backendReady = false

    deinit {
        unloadLocked()
    }

    func load(modelPath: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if context != nil { return }
        if !backendReady {
            llama_backend_init()
            backendReady = true
        }

        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #else
        modelParams.n_gpu_layers = 99
        #endif

        guard let loaded = llama_model_load_from_file(modelPath, modelParams) else {
            throw LlamaMetalEngineError.couldNotLoadModel
        }
        model = loaded
        vocab = llama_model_get_vocab(loaded)

        let nThreads = max(1, min(6, ProcessInfo.processInfo.processorCount - 1))
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 1024
        ctxParams.n_threads = Int32(nThreads)
        ctxParams.n_threads_batch = Int32(nThreads)

        guard let ctx = llama_init_from_model(loaded, ctxParams) else {
            llama_model_free(loaded)
            model = nil
            vocab = nil
            throw LlamaMetalEngineError.couldNotCreateContext
        }
        context = ctx
        batch = llama_batch_init(512, 0, 1)

        let sparams = llama_sampler_chain_default_params()
        let chain = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.5))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(42))
        sampling = chain
    }

    func unload() {
        lock.lock()
        defer { lock.unlock() }
        unloadLocked()
    }

    func complete(prompt: String, maxTokens: Int32) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LlamaMetalEngineError.emptyPrompt }
        guard let context, let vocab, let sampling, var batch else {
            throw LlamaMetalEngineError.couldNotCreateContext
        }

        llama_kv_self_clear(context)

        let tokens = tokenize(text: trimmed, vocab: vocab, addBOS: true)
        guard !tokens.isEmpty else { throw LlamaMetalEngineError.emptyPrompt }

        llama_batch_clear(&batch)
        for (i, token) in tokens.enumerated() {
            llama_batch_add(&batch, token, Int32(i), [0], false)
        }
        batch.logits[Int(batch.n_tokens) - 1] = 1
        if llama_decode(context, batch) != 0 {
            throw LlamaMetalEngineError.decodeFailed
        }

        var nCur = batch.n_tokens
        var pieces: [CChar] = []
        var output = ""
        let limit = max(8, maxTokens)

        for _ in 0..<limit {
            let tokenID = llama_sampler_sample(sampling, context, batch.n_tokens - 1)
            if llama_vocab_is_eog(vocab, tokenID) {
                break
            }
            let chars = tokenToPiece(token: tokenID, vocab: vocab)
            pieces.append(contentsOf: chars)
            if let chunk = String(bytes: pieces.map { UInt8(bitPattern: $0) }, encoding: .utf8) {
                pieces.removeAll()
                output += chunk
                if shouldStop(output: output) { break }
            }

            llama_batch_clear(&batch)
            llama_batch_add(&batch, tokenID, nCur, [0], true)
            nCur += 1
            if llama_decode(context, batch) != 0 {
                throw LlamaMetalEngineError.decodeFailed
            }
        }

        if !pieces.isEmpty,
           let tail = String(bytes: pieces.map { UInt8(bitPattern: $0) }, encoding: .utf8) {
            output += tail
        }
        self.batch = batch
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func unloadLocked() {
        if let sampling { llama_sampler_free(sampling) }
        sampling = nil
        if let batch { llama_batch_free(batch) }
        batch = nil
        if let context { llama_free(context) }
        context = nil
        if let model { llama_model_free(model) }
        model = nil
        vocab = nil
        if backendReady {
            llama_backend_free()
            backendReady = false
        }
    }

    private func shouldStop(output: String) -> Bool {
        if output.contains("\n\n") { return true }
        if output.count > 420 { return true }
        return false
    }

    private func tokenize(text: String, vocab: OpaquePointer, addBOS: Bool) -> [llama_token] {
        let utf8Count = text.utf8.count
        let capacity = utf8Count + (addBOS ? 1 : 0) + 8
        let buffer = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        let count = llama_tokenize(
            vocab,
            text,
            Int32(utf8Count),
            buffer,
            Int32(capacity),
            addBOS,
            true
        )
        guard count > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: buffer, count: Int(count)))
    }

    private func tokenToPiece(token: llama_token, vocab: OpaquePointer) -> [CChar] {
        let buf = UnsafeMutablePointer<CChar>.allocate(capacity: 16)
        defer { buf.deallocate() }
        let n = llama_token_to_piece(vocab, token, buf, 16, 0, false)
        if n < 0 {
            let size = Int(-n)
            let big = UnsafeMutablePointer<CChar>.allocate(capacity: size)
            defer { big.deallocate() }
            let m = llama_token_to_piece(vocab, token, big, Int32(size), 0, false)
            guard m > 0 else { return [] }
            return Array(UnsafeBufferPointer(start: big, count: Int(m)))
        }
        guard n > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: buf, count: Int(n)))
    }
}

private func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

private func llama_batch_add(
    _ batch: inout llama_batch,
    _ id: llama_token,
    _ pos: llama_pos,
    _ seqIDs: [llama_seq_id],
    _ logits: Bool
) {
    let i = Int(batch.n_tokens)
    batch.token[i] = id
    batch.pos[i] = pos
    batch.n_seq_id[i] = Int32(seqIDs.count)
    for (j, seq) in seqIDs.enumerated() {
        batch.seq_id[i]![j] = seq
    }
    batch.logits[i] = logits ? 1 : 0
    batch.n_tokens += 1
}
