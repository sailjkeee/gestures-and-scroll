import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func drawIcon(pixelSize: Int) throws -> Data {
    guard let context = CGContext(
        data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.scaleBy(x: CGFloat(pixelSize) / 256, y: CGFloat(pixelSize) / 256)
    context.setFillColor(red: 0.08, green: 0.17, blue: 0.25, alpha: 1)
    context.addPath(CGPath(roundedRect: CGRect(x: 22, y: 22, width: 212, height: 212),
                           cornerWidth: 48, cornerHeight: 48, transform: nil))
    context.fillPath()

    context.setLineWidth(8)
    context.setStrokeColor(red: 0.78, green: 0.88, blue: 0.94, alpha: 1)
    context.addPath(CGPath(roundedRect: CGRect(x: 64, y: 76, width: 128, height: 104),
                           cornerWidth: 18, cornerHeight: 18, transform: nil))
    context.strokePath()

    context.setLineWidth(8)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(red: 0.43, green: 0.86, blue: 0.88, alpha: 1)
    context.move(to: CGPoint(x: 113, y: 110))
    context.addLine(to: CGPoint(x: 113, y: 145))
    context.addLines(between: [CGPoint(x: 102, y: 134), CGPoint(x: 113, y: 145), CGPoint(x: 124, y: 134)])
    context.move(to: CGPoint(x: 144, y: 145))
    context.addLine(to: CGPoint(x: 144, y: 110))
    context.addLines(between: [CGPoint(x: 133, y: 121), CGPoint(x: 144, y: 110), CGPoint(x: 155, y: 121)])
    context.strokePath()

    let png = NSMutableData()
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return png as Data
}

func appendSize(_ size: Int, to data: inout Data) {
    var encoded = UInt32(size).bigEndian
    withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
}

// ICNS stores each PNG representation with a four-byte kind and length.
var images = Data()
for (kind, size) in [
    ("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
    ("ic08", 256), ("ic09", 512), ("ic10", 1024)
] {
    let png = try drawIcon(pixelSize: size)
    images.append(contentsOf: kind.utf8)
    appendSize(png.count + 8, to: &images)
    images.append(png)
}

var icon = Data("icns".utf8)
appendSize(images.count + 8, to: &icon)
icon.append(images)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
