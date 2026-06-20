import AVFoundation
import Dispatch
import Foundation
import ImageIO

protocol MediaDimensionsInspecting {
    func dimensions(for url: URL, kind: MediaKind) -> PixelDimensions?
}

struct NativeMediaDimensionsInspector: MediaDimensionsInspecting {
    func dimensions(for url: URL, kind: MediaKind) -> PixelDimensions? {
        switch kind {
        case .image:
            return imageDimensions(for: url)
        case .video:
            return videoDimensions(for: url)
        case .audio, .pdf, .folder, .unknown:
            return nil
        }
    }

    private func imageDimensions(for url: URL) -> PixelDimensions? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
              ) as? [CFString: Any],
              let rawWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let rawHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?
            .intValue ?? 1
        let swapsAxes = [5, 6, 7, 8].contains(orientation)
        return Self.positiveDimensions(
            width: swapsAxes ? rawHeight.doubleValue : rawWidth.doubleValue,
            height: swapsAxes ? rawWidth.doubleValue : rawHeight.doubleValue
        )
    }

    private func videoDimensions(for url: URL) -> PixelDimensions? {
        let asset = AVURLAsset(url: url)
        let load = VideoDimensionsLoad()
        Task {
            defer { load.semaphore.signal() }
            do {
                guard let track = try await asset.loadTracks(
                    withMediaType: .video
                ).first else {
                    return
                }
                let naturalSize = try await track.load(.naturalSize)
                let preferredTransform = try await track.load(.preferredTransform)
                load.dimensions = Self.videoDisplayDimensions(
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform
                )
            } catch {
                return
            }
        }
        load.semaphore.wait()
        return load.dimensions
    }

    static func videoDisplayDimensions(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> PixelDimensions? {
        let bounds = CGRect(
            origin: .zero,
            size: naturalSize
        ).applying(preferredTransform).standardized
        return positiveDimensions(width: bounds.width, height: bounds.height)
    }

    private static func positiveDimensions(
        width: Double,
        height: Double
    ) -> PixelDimensions? {
        let width = Int(width.rounded())
        let height = Int(height.rounded())
        guard width > 0, height > 0 else {
            return nil
        }
        return PixelDimensions(width: width, height: height)
    }
}

private final class VideoDimensionsLoad: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    var dimensions: PixelDimensions?
}
