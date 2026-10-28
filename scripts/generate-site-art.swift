// 只绘制公开品牌图形，不读取桌面、账号或用户配置。
import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
func render(_ name: String, width: Int, height: Int, social: Bool) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let blue = NSColor(calibratedRed: 0.14, green: 0.36, blue: 0.84, alpha: 1)
    let side: CGFloat = social ? 100 : CGFloat(width)
    let x: CGFloat = social ? 80 : 0, y: CGFloat = social ? 410 : 0
    if social {
        NSColor(calibratedRed: 0.965, green: 0.969, blue: 0.953, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
    }
    blue.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: side, height: side), xRadius: side*0.22, yRadius: side*0.22).fill()
    let text = "⌘" as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: side*0.75, weight: .semibold), .foregroundColor: NSColor.white]
    let size = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: x+(side-size.width)/2, y: y+(side-size.height)/2), withAttributes: attributes)
    if social {
        ("Hotkey" as NSString).draw(at: NSPoint(x: 210, y: 418), withAttributes: [.font: NSFont.systemFont(ofSize: 64, weight: .bold), .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)])
        ("常用应用，一键到达。" as NSString).draw(at: NSPoint(x: 80, y: 250), withAttributes: [.font: NSFont.systemFont(ofSize: 72, weight: .bold), .foregroundColor: blue])
        ("原生 macOS 快捷键工具 · 开源 · 配置只存本机" as NSString).draw(at: NSPoint(x: 80, y: 150), withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.darkGray])
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
}
try render("favicon-32.png", width: 32, height: 32, social: false)
try render("apple-touch-icon.png", width: 180, height: 180, social: false)
try render("social-card.png", width: 1200, height: 630, social: true)
