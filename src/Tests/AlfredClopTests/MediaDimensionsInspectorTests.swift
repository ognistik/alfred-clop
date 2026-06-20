import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AlfredClop

struct MediaDimensionsInspectorTests {
    @Test
    func imageDimensionsHonorDisplayOrientation() throws {
        let file = try temporaryFile(named: "rotated image.png")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: 3,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(
            file as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: 6] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))

        let dimensions = NativeMediaDimensionsInspector().dimensions(
            for: file,
            kind: .image
        )

        #expect(dimensions == PixelDimensions(width: 2, height: 3))
    }

    @Test
    func videoDimensionsHonorPortraitTrackTransform() {
        let dimensions = NativeMediaDimensionsInspector.videoDisplayDimensions(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: CGAffineTransform(
                a: 0,
                b: 1,
                c: -1,
                d: 0,
                tx: 1080,
                ty: 0
            )
        )

        #expect(dimensions == PixelDimensions(width: 1080, height: 1920))
    }
}
