import AppKit

let target = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let development = CommandLine.arguments[2] == "dev"
try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
for (name, size) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    NSColor(calibratedRed: 0.12, green: 0.37, blue: 0.84, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 200, yRadius: 200).fill()
    let symbol = "⌘" as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 650, weight: .medium), .foregroundColor: NSColor.white]
    let bounds = symbol.size(withAttributes: attributes)
    symbol.draw(at: NSPoint(x: (1024-bounds.width)/2, y: (1024-bounds.height)/2 + 10), withAttributes: attributes)
    if development {
        NSColor.systemOrange.setFill()
        NSBezierPath(roundedRect: NSRect(x: 390, y: 65, width: 585, height: 265), xRadius: 70, yRadius: 70).fill()
        ("DEV" as NSString).draw(at: NSPoint(x: 444, y: 82), withAttributes: [.font: NSFont.systemFont(ofSize: 195, weight: .heavy), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: target.appendingPathComponent("icon_\(name).png"))
}

// ICNS 由大端长度的图像块组成；使用 PNG 块，避免调用图像转换服务。
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
var chunks = Data()
for (type, name) in [("ic07", "128x128"), ("ic08", "256x256"), ("ic09", "512x512"), ("ic10", "512x512@2x")] {
    let png = try Data(contentsOf: target.appendingPathComponent("icon_\(name).png"))
    chunks.append(Data(type.utf8)); chunks.append(bigEndian(png.count + 8)); chunks.append(png)
}
var family = Data("icns".utf8)
family.append(bigEndian(chunks.count + 8)); family.append(chunks)
try family.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
