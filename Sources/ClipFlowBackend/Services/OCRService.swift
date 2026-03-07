import Foundation
import Vision
import AppKit
import ClipFlowCore

// MARK: - OCR Service

@MainActor
public class OCRService {
    public static let shared = OCRService()
    private init() {}

    /// Runs VNRecognizeTextRequest on a background thread and returns recognised text.
    public func recognizeText(from imageData: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let nsImage = NSImage(data: imageData),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { throw OCRError.invalidImage }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])

            // Read results directly after perform() returns — no mutable closure capture needed.
            let strings = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }

            guard !strings.isEmpty else { throw OCRError.noTextFound }
            return strings.joined(separator: "\n")
        }.value
    }
}

// MARK: - OCR Errors

public enum OCRError: LocalizedError {
    case invalidImage
    case noTextFound

    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not load image for text recognition."
        case .noTextFound: return "No text was detected in this image."
        }
    }
}
