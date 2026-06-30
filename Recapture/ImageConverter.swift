import AppKit
import ImageIO
import SDWebImage
import SDWebImageWebPCoder
import UniformTypeIdentifiers

enum ImageConverter {
    static func convert(sourceURL: URL, destinationURL: URL, outputFormat: OutputFormat, quality: Int) -> Bool {
        guard outputFormat != .original, let typeIdentifier = outputFormat.typeIdentifier else {
            return false
        }

        let normalizedQuality = max(1, min(100, quality))

        if
            let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, typeIdentifier as CFString, 1, nil)
        {
            let properties: [CFString: Any] = outputFormat.supportsCompressionQuality
                ? [kCGImageDestinationLossyCompressionQuality: Double(normalizedQuality) / 100.0]
                : [:]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            if CGImageDestinationFinalize(destination) {
                return true
            }
            try? FileManager.default.removeItem(at: destinationURL)
        }

        return convertWithBundledCoder(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            outputFormat: outputFormat,
            quality: normalizedQuality
        )
    }

    private static func convertWithBundledCoder(
        sourceURL: URL,
        destinationURL: URL,
        outputFormat: OutputFormat,
        quality: Int
    ) -> Bool {
        guard outputFormat == .webp, let image = NSImage(contentsOf: sourceURL) else {
            return false
        }

        let options: [SDImageCoderOption: Any] = [
            .encodeCompressionQuality: Double(quality) / 100.0
        ]

        do {
            guard
                let data = SDImageWebPCoder.shared.encodedData(
                    with: image,
                    format: .webP,
                    options: options
                )
            else {
                return false
            }
            try data.write(to: destinationURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
