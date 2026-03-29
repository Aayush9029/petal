import Foundation

/// Minimal tokenizer for Cohere Transcribe — handles token ID → text decoding
/// and prompt token construction from the HuggingFace tokenizer.json format.
struct CohereTokenizer {
    /// Maps token ID → token string.
    private let vocab: [Int: String]
    /// Maps token string → token ID.
    private let tokenToId: [String: Int]
    /// Set of special/added token strings to skip during decode.
    private let specialTokens: Set<String>

    init(modelDirectory: URL) throws {
        let tokenizerURL = modelDirectory.appendingPathComponent("tokenizer.json")
        let data = try Data(contentsOf: tokenizerURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // Extract vocabulary from the model section
        var idToToken = [Int: String]()
        var tokenToIdMap = [String: Int]()

        if let model = json["model"] as? [String: Any],
           let vocab = model["vocab"] as? [String: Any]
        {
            for (token, idValue) in vocab {
                if let id = idValue as? Int {
                    idToToken[id] = token
                    tokenToIdMap[token] = id
                }
            }
        }

        // Extract added tokens
        var specials = Set<String>()
        if let addedTokens = json["added_tokens"] as? [[String: Any]] {
            for tokenInfo in addedTokens {
                guard let content = tokenInfo["content"] as? String,
                      let id = tokenInfo["id"] as? Int
                else { continue }
                idToToken[id] = content
                tokenToIdMap[content] = id
                if tokenInfo["special"] as? Bool == true {
                    specials.insert(content)
                }
            }
        }

        self.vocab = idToToken
        self.tokenToId = tokenToIdMap
        self.specialTokens = specials
    }

    /// Builds the prompt token IDs that precede generated transcription tokens.
    ///
    /// Matches the NeMo cohere_asr prompt format:
    /// `<|startofcontext|> <|source_lang|> <|target_lang|> <|pnc|> <|notimestamp|> <|nodiarize|> <|emo:undefined|> <|noitn|>`
    func buildPromptTokenIds(decoderStartTokenId: Int, language: String) -> [Int] {
        var tokens = [Int]()

        // Start of context marker
        if let startCtxId = tokenToId["<|startofcontext|>"] {
            tokens.append(startCtxId)
        }

        // Source language
        if let langId = tokenToId["<|\(language)|>"] {
            tokens.append(langId)
        }

        // Target language (same as source for transcription)
        if let langId = tokenToId["<|\(language)|>"] {
            tokens.append(langId)
        }

        // Punctuation and capitalization
        if let pncId = tokenToId["<|pnc|>"] {
            tokens.append(pncId)
        }

        // No timestamps
        if let notsId = tokenToId["<|notimestamp|>"] {
            tokens.append(notsId)
        }

        // No diarization
        if let nodiarId = tokenToId["<|nodiarize|>"] {
            tokens.append(nodiarId)
        }

        // Emotion undefined
        if let emoId = tokenToId["<|emo:undefined|>"] {
            tokens.append(emoId)
        }

        // No ITN
        if let noitnId = tokenToId["<|noitn|>"] {
            tokens.append(noitnId)
        }

        return tokens
    }

    /// Decodes a sequence of token IDs into text, skipping special tokens.
    func decode(tokenIds: [Int]) -> String {
        var pieces = [String]()

        for id in tokenIds {
            guard let token = vocab[id] else { continue }

            // Skip special tokens
            if specialTokens.contains(token) { continue }
            if token.hasPrefix("<|") && token.hasSuffix("|>") { continue }

            pieces.append(token)
        }

        // Join and handle SentencePiece conventions:
        // "▁" (U+2581) represents a space before the token
        var text = pieces.joined()
        text = text.replacingOccurrences(of: "\u{2581}", with: " ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }
}
