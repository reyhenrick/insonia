import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// Gera os assets do Insonia.icon.
//
// A HIG do macOS 26+ manda entregar só a arte: sem máscara arredondada, sem
// sombra, sem especular, sem fundo pintado. O fundo é o `fill` do documento e
// quem aplica material, máscara e sombra é o sistema.
//
//   bolt.png     glifo branco em fundo transparente (a camada)
//   surface.png  textura opcional (vai para a raiz do projeto, NÃO para o
//                pacote: o ícone final usa o gradiente do documento)
//
//   swiftc -target arm64-apple-macos26.0 makeicon.swift -o /tmp/makeicon && /tmp/makeicon

let side: CGFloat = 1024
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Insonia.icon/Assets")

func newCanvas() -> (NSBitmapImageRep, CGContext) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(side), pixelsHigh: Int(side),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    return (rep, NSGraphicsContext.current!.cgContext)
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    NSGraphicsContext.restoreGraphicsState()
    let url = assets.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("gerado \(name)")
}

// MARK: - glifo

// Raio desenhado à mão. Não é SF Symbol de propósito: a licença do SF Symbols
// não permite usar os símbolos em ícones de app (só na interface).
let boltPoints: [CGPoint] = [
    CGPoint(x: 554, y: 232), CGPoint(x: 274, y: 568), CGPoint(x: 470, y: 568),
    CGPoint(x: 442, y: 792), CGPoint(x: 750, y: 456), CGPoint(x: 554, y: 456),
]

let bolt = CGMutablePath()
for (i, p) in boltPoints.enumerated() {
    let flipped = CGPoint(x: p.x, y: side - p.y)  // CG tem origem embaixo
    i == 0 ? bolt.move(to: flipped) : bolt.addLine(to: flipped)
}
bolt.closeSubpath()

let (glyphRep, glyphCtx) = newCanvas()
glyphCtx.addPath(bolt)
glyphCtx.setFillColor(NSColor.white.cgColor)
glyphCtx.fillPath()
write(glyphRep, "bolt.png")

// MARK: - textura

/// Desfoca a arte generativa até virar superfície, não desenho — o raio dela
/// vira só cor. Amplia antes porque o blur come as bordas.
func surface(from image: NSImage) -> CGImage? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let cg = rep.cgImage else { return nil }

    let ci = CIImage(cgImage: cg)
    let overscan: CGFloat = 1.6
    let scale = side * overscan / CGFloat(cg.width)

    let blur = CIFilter.gaussianBlur()
    blur.inputImage = ci.transformed(by: .init(scaleX: scale, y: scale))
    blur.radius = Float(side * 0.11)

    let tone = CIFilter.colorControls()
    tone.inputImage = blur.outputImage
    tone.saturation = 1.25
    tone.brightness = -0.30

    guard let output = tone.outputImage else { return nil }
    let crop = CGRect(x: (side * overscan - side) / 2,
                      y: (side * overscan - side) / 2,
                      width: side, height: side)
    return CIContext().createCGImage(output, from: crop)
}

if let art = NSImage(contentsOf: root.appendingPathComponent("icon-source.png")),
   let texture = surface(from: art) {
    let (rep, ctx) = newCanvas()
    ctx.draw(texture, in: CGRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    let url = root.appendingPathComponent("surface.png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("gerado surface.png (fora do pacote)")
}
