import Cocoa
import ImageIO

func makeThumbnailImage(path: String, maxPixelSize: CGFloat) -> NSImage? {
  let access = securityScopedAccess(
    url: URL(fileURLWithPath: path),
    bookmarkData: GalleryIndexStore.shared.bookmarkData(for: path)
  )
  defer { access.stop() }
  let url = access.url as CFURL
  let sourceOptions = [
    kCGImageSourceShouldCache: false
  ] as CFDictionary
  guard let source = CGImageSourceCreateWithURL(url, sourceOptions) else {
    return nil
  }

  let thumbnailOptions = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
  ] as CFDictionary

  guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
    return nil
  }

  return NSImage(
    cgImage: cgImage,
    size: CGSize(width: cgImage.width, height: cgImage.height)
  )
}

func loadImageForRendering(path: String) -> NSImage? {
  let access = securityScopedAccess(
    url: URL(fileURLWithPath: path),
    bookmarkData: GalleryIndexStore.shared.bookmarkData(for: path)
  )
  defer { access.stop() }
  let url = access.url as CFURL
  let options = [
    kCGImageSourceShouldCache: true,
    kCGImageSourceShouldCacheImmediately: true
  ] as CFDictionary

  if let source = CGImageSourceCreateWithURL(url, options),
     let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options) {
    return NSImage(
      cgImage: cgImage,
      size: CGSize(width: cgImage.width, height: cgImage.height)
    )
  }

  return NSImage(contentsOf: access.url)
}

func saveImage(image: NSImage, isTemporary: Bool) -> String? {
  let store = SettingsStore.shared
  let preset = ExportPreset.preset(for: store.exportPresetID)
  return ExportService.shared.save(
    image: image,
    isTemporary: isTemporary,
    preset: preset,
    filenameTemplate: store.filenameTemplate
  )
}
