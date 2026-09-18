#!/usr/bin/env swift
// Glancie 앱 아이콘 생성기.
// 메뉴바에서 쓰는 sparkles 글리프를 macOS 아이콘 그리드(1024 캔버스 / 824 본체)에
// 얹어 1024x1024 PNG를 뽑는다. .icns 포장은 scripts/make_icon.sh 가 맡는다.

import AppKit

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png"

let canvas: CGFloat = 1024
let inset: CGFloat = 100          // 824pt 본체 → 상하좌우 100pt 여백
let bodyRect = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let corner: CGFloat = 185.4       // Apple 아이콘 그리드 곡률

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha)
}

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("그래픽 컨텍스트를 못 잡았다")
}
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

let body = NSBezierPath(roundedRect: bodyRect, xRadius: corner, yRadius: corner)

// 본체: UsageColorTheme 의 steady 블루 그라데이션
NSGraphicsContext.saveGraphicsState()
body.addClip()
let base = NSGradient(colors: [color(0x2E9BFF), color(0x0A84FF), color(0x0050C7)],
                      atLocations: [0.0, 0.45, 1.0],
                      colorSpace: .sRGB)!
base.draw(in: bodyRect, angle: -90)

// 위쪽 하이라이트 — 유리 재질 느낌의 얕은 광택.
// 본체 전체에 걸쳐 위에서 아래로 사라지게 깔아야 중간선에 경계가 생기지 않는다.
let gloss = NSGradient(colors: [NSColor(white: 1, alpha: 0.30),
                                NSColor(white: 1, alpha: 0.10),
                                NSColor(white: 1, alpha: 0.0)],
                       atLocations: [0.0, 0.35, 0.72],
                       colorSpace: .sRGB)!
gloss.draw(in: bodyRect, angle: -90)
NSGraphicsContext.restoreGraphicsState()

// 테두리 — 밝은 배경에서 본체 경계가 뭉개지지 않게
NSColor(white: 1, alpha: 0.22).setStroke()
body.lineWidth = 3
body.stroke()

// 글리프: 메뉴바 아이템과 같은 sparkles
let glyphBox = bodyRect.insetBy(dx: bodyRect.width * 0.21, dy: bodyRect.height * 0.21)
let config = NSImage.SymbolConfiguration(pointSize: glyphBox.height, weight: .semibold)
guard let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Glancie")?
        .withSymbolConfiguration(config) else {
    fatalError("sparkles 심볼을 못 불러왔다")
}

let size = symbol.size
let scale = min(glyphBox.width / size.width, glyphBox.height / size.height)
let drawn = NSSize(width: size.width * scale, height: size.height * scale)
let glyphRect = NSRect(x: bodyRect.midX - drawn.width / 2,
                       y: bodyRect.midY - drawn.height / 2,
                       width: drawn.width,
                       height: drawn.height)

// 글리프 밑에 떨어뜨리는 그림자로 파란 배경과 분리
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10),
              blur: 26,
              color: color(0x00214D, alpha: 0.35).cgColor)
let tinted = NSImage(size: symbol.size)
tinted.lockFocus()
NSColor.white.set()
NSRect(origin: .zero, size: symbol.size).fill()
symbol.draw(at: .zero, from: NSRect(origin: .zero, size: symbol.size),
            operation: .destinationIn, fraction: 1)
tinted.unlockFocus()
tinted.draw(in: glyphRect, from: NSRect(origin: .zero, size: symbol.size),
            operation: .sourceOver, fraction: 1)
ctx.restoreGState()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG 인코딩에 실패했다")
}

try! png.write(to: URL(fileURLWithPath: outputPath))
print("🎨 \(outputPath)")
