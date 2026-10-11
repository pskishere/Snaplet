import AppKit
import ImageIO
import UniformTypeIdentifiers

struct EncodedImage {
    let data: Data
    let width: Int
    let height: Int
}

enum ImageOutput {
    static func encode(_ image: CGImage, format: String = "png", quality: Double = 1) throws -> EncodedImage {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, (format == "png" ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return EncodedImage(data: data as Data, width: image.width, height: image.height)
    }
    static func export(sourceURL: URL, destinationURL: URL, scale: Double, format: String, quality: Double) async throws -> EncodedImage {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw CocoaError(.fileReadCorruptFile) }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max(1, Int(Double(max(width, height)) * scale)), kCGImageSourceCreateThumbnailWithTransform: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
            let result = try encode(image, format: format, quality: quality)
            try result.data.write(to: destinationURL, options: .atomic)
            return result
        }.value
    }
    static func annotate(original: CGImage, marks: [AnnotationMark], destinationURL: URL?) async throws -> EncodedImage {
        try await Task.detached(priority: .userInitiated) {
            // A worker owns its renderer and bitmap context; it never shares the canvas renderer.
            let renderer = AnnotationRenderer(original: original)
            guard let image = renderer.render(marks) else { throw CocoaError(.fileReadCorruptFile) }
            let result = try encode(image)
            if let destinationURL { try result.data.write(to: destinationURL, options: .atomic) }
            return result
        }.value
    }
}
