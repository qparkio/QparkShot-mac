import Cocoa
import CoreImage
import SwiftUI

enum ToolType {
  case select, freehand, arrow, rectangle, text, redact, blur, callout
}

struct Annotation: Identifiable, Equatable {
  let id = UUID()
  var type: ToolType
  var color: Color
  var strokeWidth: CGFloat
  var points: [CGPoint] = []
  var text: String = ""
  var rect: CGRect = .zero
  var calloutNumber: Int = 0

  static func == (lhs: Annotation, rhs: Annotation) -> Bool {
    lhs.id == rhs.id
  }
}

struct DrawingCanvas: View {
  let image: NSImage
  @Binding var annotations: [Annotation]
  @Binding var currentTool: ToolType
  @Binding var currentColor: Color
  @Binding var currentStrokeWidth: CGFloat
  @Binding var textInput: String
  @Binding var cropRect: CGRect?
  let onAction: () -> Void

  @State private var renderedAnnotations: NSImage?
  @State private var currentPoints: [CGPoint] = []
  @State private var dragStart: CGPoint?
  @State private var dragCurrent: CGPoint?

  var body: some View {
    GeometryReader { geo in
      let imageRect = fittedImageRect(imageSize: image.size, in: geo.size)
      let imageScale = imageRect.width / max(image.size.width, 1)

      ZStack {
        Image(nsImage: renderedAnnotations ?? image)
          .resizable()
          .frame(width: imageRect.width, height: imageRect.height)
          .position(x: imageRect.midX, y: imageRect.midY)

        Canvas { context, _ in
          var drawingContext = context
          drawingContext.clip(to: Path(imageRect))
          drawingContext.translateBy(x: imageRect.minX, y: imageRect.minY)
          drawingContext.scaleBy(x: imageScale, y: imageScale)

          drawActiveGesture(in: &drawingContext)
        }

        if let cropRect {
          let crop = CGRect(
            x: imageRect.minX + cropRect.minX * imageScale,
            y: imageRect.minY + cropRect.minY * imageScale,
            width: cropRect.width * imageScale,
            height: cropRect.height * imageScale
          )
          Path { path in
            path.addRect(imageRect)
            path.addRect(crop)
          }
          .fill(.black.opacity(0.4), style: FillStyle(eoFill: true))
          .allowsHitTesting(false)
          Path(crop).stroke(.white, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .allowsHitTesting(false)
        }
      }
      .gesture(canvasGesture(in: imageRect, imageSize: image.size))
    }
    .task(id: annotations) {
      let snapshot = annotations
      let source = image
      let rendered = await Task.detached(priority: .userInitiated) {
        ExportService.shared.render(ExportContext(
          image: source, annotations: snapshot, cropRect: nil,
          preset: .clean, watermark: .disabled
        ))
      }.value
      guard !Task.isCancelled else { return }
      renderedAnnotations = rendered
    }
  }

  private func canvasGesture(in imageRect: CGRect, imageSize: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if dragStart == nil {
          guard imageRect.contains(value.startLocation) else { return }
          let start = imagePoint(
            for: value.startLocation,
            imageRect: imageRect,
            imageSize: imageSize
          )
          dragStart = start
          currentPoints = [start]
        }

        let point = imagePoint(
          for: value.location,
          imageRect: imageRect,
          imageSize: imageSize
        )
        dragCurrent = point
        if currentTool == .freehand {
          currentPoints.append(point)
        }
      }
      .onEnded { value in
        guard let start = dragStart else { return }
        let end = imagePoint(
          for: value.location,
          imageRect: imageRect,
          imageSize: imageSize
        )

        commitGesture(from: start, to: end)
        dragStart = nil
        dragCurrent = nil
        currentPoints = []
      }
  }

  private func commitGesture(from start: CGPoint, to end: CGPoint) {
    switch currentTool {
    case .freehand:
      if currentPoints.count > 1 {
        annotations.append(
          Annotation(
            type: .freehand,
            color: currentColor,
            strokeWidth: currentStrokeWidth,
            points: currentPoints
          )
        )
        onAction()
      }
    case .rectangle:
      annotations.append(
        Annotation(
          type: .rectangle,
          color: currentColor,
          strokeWidth: currentStrokeWidth,
          rect: CGRect(from: start, to: end)
        )
      )
      onAction()
    case .arrow:
      annotations.append(
        Annotation(
          type: .arrow,
          color: currentColor,
          strokeWidth: currentStrokeWidth,
          points: [start, end]
        )
      )
      onAction()
    case .text:
      if !textInput.isEmpty {
        annotations.append(
          Annotation(
            type: .text,
            color: currentColor,
            strokeWidth: currentStrokeWidth,
            points: [start],
            text: textInput
          )
        )
        onAction()
      }
    case .redact:
      annotations.append(
        Annotation(
          type: .redact,
          color: .black,
          strokeWidth: currentStrokeWidth,
          rect: CGRect(from: start, to: end)
        )
      )
      onAction()
    case .blur:
      annotations.append(
        Annotation(
          type: .blur,
          color: .gray,
          strokeWidth: currentStrokeWidth,
          rect: CGRect(from: start, to: end)
        )
      )
      onAction()
    case .callout:
      annotations.append(
        Annotation(
          type: .callout,
          color: currentColor,
          strokeWidth: currentStrokeWidth,
          points: [start],
          calloutNumber: nextCalloutNumber()
        )
      )
      onAction()
    case .select:
      let rect = CGRect(from: start, to: end).standardized
      guard rect.width >= 1, rect.height >= 1 else { return }
      cropRect = rect
      onAction()
    }
  }

  private func nextCalloutNumber() -> Int {
    let highestNumber = annotations
      .filter { $0.type == .callout }
      .map(\.calloutNumber)
      .max() ?? 0
    return highestNumber + 1
  }

  private func drawActiveGesture(in context: inout GraphicsContext) {
    guard let dragStart, let dragCurrent else { return }

    var path = Path()
    switch currentTool {
    case .freehand:
      if currentPoints.count > 1 {
        path.addLines(currentPoints)
        context.stroke(path, with: .color(currentColor), lineWidth: currentStrokeWidth)
      }
    case .rectangle:
      path.addRect(CGRect(from: dragStart, to: dragCurrent))
      context.stroke(path, with: .color(currentColor), lineWidth: currentStrokeWidth)
    case .arrow:
      drawArrow(in: &context, from: dragStart, to: dragCurrent, color: currentColor, width: currentStrokeWidth)
    case .select:
      path.addRect(CGRect(from: dragStart, to: dragCurrent))
      context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    case .redact:
      path.addRect(CGRect(from: dragStart, to: dragCurrent))
      context.fill(path, with: .color(.black.opacity(0.85)))
    case .blur:
      path.addRect(CGRect(from: dragStart, to: dragCurrent))
      context.fill(path, with: .color(.secondary.opacity(0.35)))
      context.stroke(path, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
    case .callout:
      drawCallout(
        in: &context,
        center: dragStart,
        number: nextCalloutNumber(),
        color: currentColor,
        width: currentStrokeWidth
      )
    default:
      break
    }
  }

  private func drawArrow(in context: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color, width: CGFloat) {
    var path = Path()
    path.move(to: from)
    path.addLine(to: to)
    context.stroke(path, with: .color(color), lineWidth: width)

    let angle = atan2(to.y - from.y, to.x - from.x)
    let arrowLength: CGFloat = width * 2 + 10
    let p1 = CGPoint(
      x: to.x - arrowLength * cos(angle - .pi / 6),
      y: to.y - arrowLength * sin(angle - .pi / 6)
    )
    let p2 = CGPoint(
      x: to.x - arrowLength * cos(angle + .pi / 6),
      y: to.y - arrowLength * sin(angle + .pi / 6)
    )

    var arrowHead = Path()
    arrowHead.move(to: to)
    arrowHead.addLine(to: p1)
    arrowHead.addLine(to: p2)
    arrowHead.closeSubpath()

    context.fill(arrowHead, with: .color(color))
  }

  private func drawCallout(
    in context: inout GraphicsContext,
    center: CGPoint,
    number: Int,
    color: Color,
    width: CGFloat
  ) {
    let diameter = max(width * 7, 24)
    let rect = CGRect(
      x: center.x - diameter / 2,
      y: center.y - diameter / 2,
      width: diameter,
      height: diameter
    )

    let circle = Path(ellipseIn: rect)
    context.fill(circle, with: .color(color))
    context.stroke(circle, with: .color(.white), lineWidth: max(1.5, width * 0.4))
    context.draw(
      Text("\(number)")
        .font(.system(size: diameter * 0.48, weight: .bold))
        .foregroundColor(.white),
      at: center,
      anchor: .center
    )
  }
}

struct WatermarkRenderSettings {
  let textEnabled: Bool
  let text: String
  let textColor: String
  let logoEnabled: Bool
  let logoPath: String
  let logoBookmarkData: Data?
  let opacity: Double
  let logoSize: Double
  let position: String
  let layoutMode: String
  let spacing: Double
  let tilePattern: String
  let tileRandomness: Double

  init(
    textEnabled: Bool,
    text: String,
    textColor: String,
    logoEnabled: Bool,
    logoPath: String,
    logoBookmarkData: Data? = nil,
    opacity: Double,
    logoSize: Double,
    position: String,
    layoutMode: String,
    spacing: Double,
    tilePattern: String,
    tileRandomness: Double
  ) {
    self.textEnabled = textEnabled
    self.text = text
    self.textColor = textColor
    self.logoEnabled = logoEnabled
    self.logoPath = logoPath
    self.logoBookmarkData = logoBookmarkData
    self.opacity = opacity
    self.logoSize = logoSize
    self.position = position
    self.layoutMode = layoutMode
    self.spacing = spacing
    self.tilePattern = tilePattern
    self.tileRandomness = tileRandomness
  }

  static func current(store: SettingsStore = SettingsStore.shared) -> WatermarkRenderSettings {
    WatermarkRenderSettings(
      textEnabled: store.watermarkTextEnabled,
      text: store.watermarkText,
      textColor: store.watermarkTextColor,
      logoEnabled: store.watermarkLogoEnabled,
      logoPath: store.watermarkLogoPath,
      logoBookmarkData: store.watermarkLogoBookmarkData,
      opacity: store.watermarkOpacity,
      logoSize: store.watermarkSize,
      position: store.watermarkPosition,
      layoutMode: store.watermarkLayoutMode,
      spacing: store.watermarkSpacing,
      tilePattern: store.watermarkTilePattern,
      tileRandomness: store.watermarkTileRandomness
    )
  }

  static let disabled = WatermarkRenderSettings(
    textEnabled: false,
    text: "",
    textColor: "#FFFFFF",
    logoEnabled: false,
    logoPath: "",
    logoBookmarkData: nil,
    opacity: 0,
    logoSize: 0,
    position: "bottomRight",
    layoutMode: "single",
    spacing: 150,
    tilePattern: "aligned",
    tileRandomness: 0
  )
}

func renderAnnotatedImage(
  image: NSImage,
  annotations: [Annotation],
  cropRect: CGRect?,
  watermark: WatermarkRenderSettings = .current()
) -> NSImage? {
  let imageWidth = image.size.width
  let imageHeight = image.size.height
  let imageBounds = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
  let exportRect = normalizedCropRect(cropRect, in: imageBounds)
  let watermarkTarget = CGRect(
    x: exportRect.minX,
    y: imageHeight - exportRect.maxY,
    width: exportRect.width,
    height: exportRect.height
  )

  guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(imageWidth),
    pixelsHigh: Int(imageHeight),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else { return nil }

  rep.size = image.size

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  defer {
    NSGraphicsContext.restoreGraphicsState()
  }

  let sourceCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)

  image.draw(in: NSRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
  renderAnnotations(
    annotations,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    sourceCGImage: sourceCGImage
  )
  renderWatermark(watermark, in: watermarkTarget)

  let finalImage = NSImage(size: image.size)
  finalImage.addRepresentation(rep)

  if exportRect != imageBounds {
    guard let cgImg = rep.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let croppedCg = cgImg.cropping(to: exportRect) else {
      return finalImage
    }
    return NSImage(cgImage: croppedCg, size: exportRect.size)
  }

  return finalImage
}

func fittedImageRect(imageSize: CGSize, in availableSize: CGSize) -> CGRect {
  guard imageSize.width > 0,
        imageSize.height > 0,
        availableSize.width > 0,
        availableSize.height > 0 else {
    return .zero
  }

  let scale = min(
    availableSize.width / imageSize.width,
    availableSize.height / imageSize.height
  )
  let fittedSize = CGSize(
    width: imageSize.width * scale,
    height: imageSize.height * scale
  )
  return CGRect(
    x: (availableSize.width - fittedSize.width) / 2,
    y: (availableSize.height - fittedSize.height) / 2,
    width: fittedSize.width,
    height: fittedSize.height
  )
}

func imagePoint(
  for viewPoint: CGPoint,
  imageRect: CGRect,
  imageSize: CGSize
) -> CGPoint {
  guard imageRect.width > 0, imageRect.height > 0 else {
    return .zero
  }

  let x = ((viewPoint.x - imageRect.minX) / imageRect.width) * imageSize.width
  let y = ((viewPoint.y - imageRect.minY) / imageRect.height) * imageSize.height
  return CGPoint(
    x: min(max(x, 0), imageSize.width),
    y: min(max(y, 0), imageSize.height)
  )
}

func viewPoint(
  for imagePoint: CGPoint,
  imageRect: CGRect,
  imageSize: CGSize
) -> CGPoint {
  guard imageSize.width > 0, imageSize.height > 0 else {
    return imageRect.origin
  }

  return CGPoint(
    x: imageRect.minX + (imagePoint.x / imageSize.width) * imageRect.width,
    y: imageRect.minY + (imagePoint.y / imageSize.height) * imageRect.height
  )
}

extension CGRect {
  init(from: CGPoint, to: CGPoint) {
    let x = min(from.x, to.x)
    let y = min(from.y, to.y)
    let width = abs(from.x - to.x)
    let height = abs(from.y - to.y)
    self.init(x: x, y: y, width: width, height: height)
  }
}

private func renderAnnotations(
  _ annotations: [Annotation],
  imageWidth: CGFloat,
  imageHeight: CGFloat,
  sourceCGImage: CGImage?
) {
  let context = NSGraphicsContext.current?.cgContext

  for annotation in annotations {
    context?.saveGState()

    let cgColor = NSColor(annotation.color).cgColor
    context?.setStrokeColor(cgColor)
    context?.setFillColor(cgColor)
    context?.setLineWidth(annotation.strokeWidth)
    context?.setLineCap(.round)
    context?.setLineJoin(.round)

    switch annotation.type {
    case .redact:
      renderRedaction(annotation, imageHeight: imageHeight, context: context)
    case .blur:
      renderBlur(annotation, imageHeight: imageHeight, context: context, sourceCGImage: sourceCGImage)
    case .freehand:
      renderFreehand(annotation, imageHeight: imageHeight, context: context)
    case .rectangle:
      renderRectangle(annotation, imageHeight: imageHeight, context: context)
    case .arrow:
      renderArrow(annotation, imageHeight: imageHeight, context: context)
    case .text:
      renderText(annotation, imageWidth: imageWidth, imageHeight: imageHeight)
    case .callout:
      renderCallout(annotation, imageHeight: imageHeight, context: context)
    default:
      break
    }

    context?.restoreGState()
  }
}

private func renderRedaction(_ annotation: Annotation, imageHeight: CGFloat, context: CGContext?) {
  let renderRect = flippedRenderRect(annotation.rect, imageHeight: imageHeight)
  context?.setFillColor(NSColor.black.cgColor)
  context?.fill(renderRect)
}

private func renderBlur(
  _ annotation: Annotation,
  imageHeight: CGFloat,
  context: CGContext?,
  sourceCGImage: CGImage?
) {
  guard let context, let sourceCGImage else {
    renderRedaction(annotation, imageHeight: imageHeight, context: context)
    return
  }

  let renderRect = flippedRenderRect(annotation.rect, imageHeight: imageHeight)
  guard renderRect.width >= 2,
        renderRect.height >= 2,
        let cropped = sourceCGImage.cropping(to: annotation.rect.standardized) else {
    return
  }

  let input = CIImage(cgImage: cropped)
  let filter = CIFilter(name: "CIGaussianBlur")
  filter?.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
  filter?.setValue(12.0, forKey: kCIInputRadiusKey)

  guard let output = filter?.outputImage?.cropped(to: input.extent),
        let blurred = CIContext().createCGImage(output, from: input.extent) else {
    renderRedaction(annotation, imageHeight: imageHeight, context: context)
    return
  }

  context.draw(blurred, in: renderRect)
}

private func renderFreehand(_ annotation: Annotation, imageHeight: CGFloat, context: CGContext?) {
  guard annotation.points.count > 1 else { return }

  context?.beginPath()
  let first = annotation.points[0]
  context?.move(to: CGPoint(x: first.x, y: imageHeight - first.y))
  for point in annotation.points.dropFirst() {
    context?.addLine(to: CGPoint(x: point.x, y: imageHeight - point.y))
  }
  context?.strokePath()
}

private func renderRectangle(_ annotation: Annotation, imageHeight: CGFloat, context: CGContext?) {
  let sourceRect = annotation.rect.standardized
  let flippedY = imageHeight - (sourceRect.origin.y + sourceRect.size.height)
  let renderRect = CGRect(
    x: sourceRect.origin.x,
    y: flippedY,
    width: sourceRect.size.width,
    height: sourceRect.size.height
  )
  context?.stroke(renderRect)
}

private func renderArrow(_ annotation: Annotation, imageHeight: CGFloat, context: CGContext?) {
  guard annotation.points.count == 2 else { return }

  let from = CGPoint(
    x: annotation.points[0].x,
    y: imageHeight - annotation.points[0].y
  )
  let to = CGPoint(
    x: annotation.points[1].x,
    y: imageHeight - annotation.points[1].y
  )

  context?.beginPath()
  context?.move(to: from)
  context?.addLine(to: to)
  context?.strokePath()

  let angle = atan2(to.y - from.y, to.x - from.x)
  let arrowLength = annotation.strokeWidth * 2 + 10
  let p1 = CGPoint(
    x: to.x - arrowLength * cos(angle - .pi / 6),
    y: to.y - arrowLength * sin(angle - .pi / 6)
  )
  let p2 = CGPoint(
    x: to.x - arrowLength * cos(angle + .pi / 6),
    y: to.y - arrowLength * sin(angle + .pi / 6)
  )

  context?.beginPath()
  context?.move(to: to)
  context?.addLine(to: p1)
  context?.addLine(to: p2)
  context?.closePath()
  context?.fillPath()
}

private func renderText(_ annotation: Annotation, imageWidth: CGFloat, imageHeight: CGFloat) {
  guard let first = annotation.points.first else { return }

  let fontSize = annotation.strokeWidth * 3 + 12
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: fontSize),
    .foregroundColor: NSColor(annotation.color)
  ]
  let textRect = NSRect(
    x: first.x,
    y: imageHeight - first.y - fontSize,
    width: imageWidth,
    height: imageHeight
  )
  (annotation.text as NSString).draw(in: textRect, withAttributes: attributes)
}

private func renderCallout(_ annotation: Annotation, imageHeight: CGFloat, context: CGContext?) {
  guard let context, let point = annotation.points.first else { return }

  let center = CGPoint(x: point.x, y: imageHeight - point.y)
  let diameter = max(annotation.strokeWidth * 7, 24)
  let rect = CGRect(
    x: center.x - diameter / 2,
    y: center.y - diameter / 2,
    width: diameter,
    height: diameter
  )

  context.setFillColor(NSColor(annotation.color).cgColor)
  context.fillEllipse(in: rect)
  context.setStrokeColor(NSColor.white.cgColor)
  context.setLineWidth(max(1.5, annotation.strokeWidth * 0.4))
  context.strokeEllipse(in: rect)

  let value = "\(annotation.calloutNumber)" as NSString
  let fontSize = diameter * 0.48
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: fontSize),
    .foregroundColor: NSColor.white
  ]
  let textSize = value.size(withAttributes: attributes)
  let textRect = NSRect(
    x: center.x - textSize.width / 2,
    y: center.y - textSize.height / 2,
    width: textSize.width,
    height: textSize.height
  )
  value.draw(in: textRect, withAttributes: attributes)
}

private func flippedRenderRect(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
  let sourceRect = rect.standardized
  return CGRect(
    x: sourceRect.origin.x,
    y: imageHeight - (sourceRect.origin.y + sourceRect.size.height),
    width: sourceRect.size.width,
    height: sourceRect.size.height
  )
}

private func renderWatermark(_ watermark: WatermarkRenderSettings, in target: CGRect) {
  if watermark.layoutMode == "tiled" {
    renderTiledWatermark(watermark, in: target)
  } else {
    renderSingleWatermark(watermark, in: target)
  }
}

private func renderTiledWatermark(_ watermark: WatermarkRenderSettings, in target: CGRect) {
  let context = NSGraphicsContext.current?.cgContext
  let opacity = CGFloat(watermark.opacity)

  context?.saveGState()
  context?.clip(to: target)
  context?.translateBy(x: target.midX, y: target.midY)
  context?.rotate(by: -CGFloat.pi / 6)
  defer {
    context?.restoreGState()
  }

  let diagonal = sqrt(target.width * target.width + target.height * target.height)
  let logo = loadWatermarkLogo(watermark)
  let text = watermarkTextLayout(watermark, fontSize: 20, opacity: opacity)
  let spacingX = CGFloat(watermark.spacing) * 1.5
  let spacingY = CGFloat(watermark.spacing) * 1.1

  var rowIndex = 0
  for y in stride(from: -diagonal, to: diagonal, by: spacingY) {
    let rowOffset = watermark.tilePattern == "brick" || watermark.tilePattern == "random"
      ? (rowIndex.isMultiple(of: 2) ? 0 : spacingX / 2)
      : 0
    var columnIndex = 0
    for x in stride(from: -diagonal, to: diagonal, by: spacingX) {
      let jitterLimit = watermark.tilePattern == "random"
        ? min(spacingX, spacingY) * CGFloat(watermark.tileRandomness) * 0.35
        : 0
      let drawX = x + rowOffset + deterministicTileJitter(row: rowIndex, column: columnIndex, salt: 1) * jitterLimit
      let drawY = y + deterministicTileJitter(row: rowIndex, column: columnIndex, salt: 2) * jitterLimit

      renderWatermarkLogo(logo, center: CGPoint(x: drawX, y: drawY), opacity: opacity)
      renderWatermarkText(text, center: CGPoint(x: drawX, y: drawY), logoHeight: logo?.size.height ?? 0)
      columnIndex += 1
    }
    rowIndex += 1
  }
}

private func renderSingleWatermark(_ watermark: WatermarkRenderSettings, in target: CGRect) {
  let opacity = CGFloat(watermark.opacity)
  let padding = min(16.0, min(target.width, target.height) * 0.12)
  let logo = loadWatermarkLogo(watermark)
  let text = watermarkTextLayout(watermark, fontSize: 24, opacity: opacity)

  if let logo {
    let logoRect = positionedRect(
      size: logo.size,
      in: target,
      position: watermark.position,
      padding: padding,
      yOffset: 0
    )
    logo.image.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: opacity)
  }

  if let text {
    let yOffset = logo == nil ? 0 : logo!.size.height + 8.0
    let textRect = positionedRect(
      size: text.size,
      in: target,
      position: watermark.position,
      padding: padding,
      yOffset: yOffset
    )
    text.value.draw(in: textRect, withAttributes: text.attributes)
  }
}

private func loadWatermarkLogo(_ watermark: WatermarkRenderSettings) -> (image: NSImage, size: CGSize)? {
  guard watermark.logoEnabled,
        !watermark.logoPath.isEmpty else {
    return nil
  }

  let access = securityScopedAccess(
    url: URL(fileURLWithPath: watermark.logoPath),
    bookmarkData: watermark.logoBookmarkData
  )
  defer { access.stop() }

  guard let image = NSImage(contentsOf: access.url),
        image.size.width > 0 else {
    return nil
  }

  let width = CGFloat(watermark.logoSize)
  let height = image.size.height * (width / image.size.width)
  return (image, CGSize(width: width, height: height))
}

private func watermarkTextLayout(
  _ watermark: WatermarkRenderSettings,
  fontSize: CGFloat,
  opacity: CGFloat
) -> (value: NSString, size: CGSize, attributes: [NSAttributedString.Key: Any])? {
  guard watermark.textEnabled, !watermark.text.isEmpty else {
    return nil
  }

  let value = watermark.text as NSString
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: fontSize),
    .foregroundColor: NSColor(hexString: watermark.textColor).withAlphaComponent(opacity)
  ]
  return (value, value.size(withAttributes: attributes), attributes)
}

private func renderWatermarkLogo(
  _ logo: (image: NSImage, size: CGSize)?,
  center: CGPoint,
  opacity: CGFloat
) {
  guard let logo else { return }

  let rect = NSRect(
    x: center.x - logo.size.width / 2,
    y: center.y - logo.size.height / 2,
    width: logo.size.width,
    height: logo.size.height
  )
  logo.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: opacity)
}

private func renderWatermarkText(
  _ text: (value: NSString, size: CGSize, attributes: [NSAttributedString.Key: Any])?,
  center: CGPoint,
  logoHeight: CGFloat
) {
  guard let text else { return }

  let textY = logoHeight > 0
    ? center.y - logoHeight / 2 - text.size.height - 6.0
    : center.y - text.size.height / 2
  let textRect = NSRect(
    x: center.x - text.size.width / 2,
    y: textY,
    width: text.size.width,
    height: text.size.height
  )
  text.value.draw(in: textRect, withAttributes: text.attributes)
}

private func positionedRect(
  size: CGSize,
  in target: CGRect,
  position: String,
  padding: CGFloat,
  yOffset: CGFloat
) -> NSRect {
  switch position {
  case "bottomRight":
    return NSRect(
      x: target.maxX - size.width - padding,
      y: target.minY + padding + yOffset,
      width: size.width,
      height: size.height
    )
  case "bottomLeft":
    return NSRect(
      x: target.minX + padding,
      y: target.minY + padding + yOffset,
      width: size.width,
      height: size.height
    )
  case "topRight":
    return NSRect(
      x: target.maxX - size.width - padding,
      y: target.maxY - size.height - padding - yOffset,
      width: size.width,
      height: size.height
    )
  case "topLeft":
    return NSRect(
      x: target.minX + padding,
      y: target.maxY - size.height - padding - yOffset,
      width: size.width,
      height: size.height
    )
  case "center":
    return NSRect(
      x: target.midX - size.width / 2,
      y: target.midY - size.height / 2 - yOffset,
      width: size.width,
      height: size.height
    )
  default:
    return .zero
  }
}

func deterministicTileJitter(row: Int, column: Int, salt: Int) -> CGFloat {
  let seed = Double(row * 12_989 + column * 78_233 + salt * 37_719)
  let raw = sin(seed) * 43_758.5453
  let fraction = raw - floor(raw)
  return CGFloat(fraction * 2 - 1)
}

private func normalizedCropRect(_ cropRect: CGRect?, in imageBounds: CGRect) -> CGRect {
  guard let cropRect else {
    return imageBounds
  }

  let crop = cropRect.standardized.intersection(imageBounds)
  if crop.isNull || crop.width < 2 || crop.height < 2 {
    return imageBounds
  }
  return crop
}
