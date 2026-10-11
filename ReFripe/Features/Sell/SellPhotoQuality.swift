import Foundation
import UIKit
import ImageIO
import CoreGraphics
import Vision
import SensitiveContentAnalysis

/// Where a photo comes from. Camera shots skip the screenshot check (they can't be one).
enum SellPhotoSource: Sendable {
    case library, camera
}

/// Result of the on-device quality check of one photo (computed off the main actor).
struct SellPhotoAnalysis: @unchecked Sendable {
    /// Normalised JPEG (oriented, ≤ 1600 px) — what gets published.
    var jpeg: Data
    /// Small preview for the grid / review / share sheet.
    var thumbnail: UIImage
    /// 64-bit difference hash (dHash) used for the duplicate check against the other photos.
    var hash: UInt64
    /// Intrinsic problem of this photo alone. `.duplicate` is evaluated by the model against the other photos.
    var flag: PhotoFlag?
    /// Diagnostics (handy to calibrate thresholds on real photos).
    var sharpness: Double
    var textCoverage: Double
}

/// Local, best-effort quality control run before a photo can be published (mockup `sell_1`).
///
/// - Flou        : variance du Laplacien sur une image en niveaux de gris réduite (768 px), calculée par tuiles
///                 4×4 ; on garde la tuile la plus nette (un sujet net sur fond flouté passe).
/// - Doublon     : dHash 64 bits (9×8), distance de Hamming ≤ `duplicateMaxDistance`.
/// - Screenshot  : EXIF « Screenshot » d'iOS, sinon dimensions/ratio d'écran de téléphone sans métadonnées d'appareil photo.
/// - Watermark   : Vision `VNRecognizeTextRequest` — mots-clés de banques d'images / boutiques, texte répété
///                 (filigrane en mosaïque) ou forte couverture de texte en surimpression.
/// - Contenu sensible : `SCSensitivityAnalyzer` (iOS 17) ; si la politique est désactivée (réglage utilisateur
///                 ou entitlement absent), le contrôle est simplement sauté.
/// - « Contenu inapproprié » n'a pas de détecteur local fiable : il reste du ressort de la modération serveur.
enum SellPhotoQuality {
    // MARK: Tunables (à calibrer sur un échantillon de vraies photos de fripe)
    static let publishMaxPixel: CGFloat = 1600
    static let thumbnailMaxPixel: CGFloat = 360
    static let analysisMaxPixel = 768
    /// Below this, even the sharpest 1/16th of the picture is considered blurry.
    static let blurThreshold: Double = 45
    static let duplicateMaxDistance = 6
    /// Share of the picture covered by recognised text above which we consider it an overlay.
    static let textCoverageThreshold: Double = 0.16
    static let textLineThreshold = 12

    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

    // MARK: Entry point

    /// Returns `nil` when the data can't be decoded as an image.
    static func analyze(_ data: Data, source: SellPhotoSource) async -> SellPhotoAnalysis? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let full = downscaled(imageSource, maxPixel: publishMaxPixel),
              let jpeg = UIImage(cgImage: full).jpegData(compressionQuality: 0.82) else { return nil }
        let thumb = downscaled(imageSource, maxPixel: thumbnailMaxPixel).map { UIImage(cgImage: $0) } ?? UIImage(cgImage: full)

        let gray = SellGrayImage(cgImage: full, maxSide: analysisMaxPixel)
        let sharpness = gray?.maxTileLaplacianVariance() ?? .infinity
        let hash = gray?.differenceHash() ?? 0

        let screenshot = source == .library && looksLikeScreenshot(imageSource)
        let sensitive = await isSensitive(full)
        let text = textOverlay(in: full)

        // Most severe first.
        var flag: PhotoFlag?
        if sensitive { flag = .nudity }
        else if screenshot { flag = .screenshot }
        else if text.isWatermark { flag = .watermark }
        else if sharpness < blurThreshold { flag = .blur }

        return SellPhotoAnalysis(jpeg: jpeg, thumbnail: thumb, hash: hash, flag: flag,
                                 sharpness: sharpness, textCoverage: text.coverage)
    }

    /// Oriented, downscaled decode (handles HEIC/JPEG/PNG and the EXIF orientation).
    private static func downscaled(_ source: CGImageSource, maxPixel: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: Screenshot

    /// Phone screen resolutions in pixels (short side, long side).
    private static let screenSizes: Set<[Int]> = [
        [640, 1136], [750, 1334], [1080, 1920], [1242, 2208], [1125, 2436], [828, 1792], [1242, 2688],
        [1080, 2340], [1170, 2532], [1284, 2778], [1179, 2556], [1290, 2796], [1206, 2622], [1320, 2868],
        [1260, 2736], [720, 1600], [1080, 2400], [1440, 3200], [1080, 2408], [720, 1612],
    ]

    static func looksLikeScreenshot(_ source: CGImageSource) -> Bool {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        // iOS writes UserComment = "Screenshot" in its screenshots.
        if let comment = exif[kCGImagePropertyExifUserComment] as? String,
           comment.localizedCaseInsensitiveContains("screenshot") { return true }

        // A real camera leaves a make/model or exposure data.
        let hasCameraMetadata = tiff[kCGImagePropertyTIFFMake] != nil || tiff[kCGImagePropertyTIFFModel] != nil
            || exif[kCGImagePropertyExifLensModel] != nil || exif[kCGImagePropertyExifExposureTime] != nil
            || exif[kCGImagePropertyExifFNumber] != nil
        if hasCameraMetadata { return false }

        guard let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { return false }
        let short = min(w, h), long = max(w, h)
        if screenSizes.contains([short, long]) { return true }
        // Modern phones are ~19.5:9 (2.17) or 20:9 (2.22); camera photos are 4:3 / 3:2 / 16:9.
        let ratio = Double(long) / Double(short)
        return ratio > 2.1 && ratio < 2.25 && short >= 600
    }

    // MARK: Text / watermark (Vision)

    private static let watermarkKeywords = [
        "shutterstock", "getty", "istock", "alamy", "dreamstime", "depositphotos", "123rf", "adobe stock",
        "stock photo", "copyright", "©", "www.", "http", ".com", "shein", "aliexpress", "alibaba", "jumia", "temu",
    ]

    struct TextOverlay { var coverage: Double; var isWatermark: Bool }

    static func textOverlay(in image: CGImage) -> TextOverlay {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["fr-FR", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return TextOverlay(coverage: 0, isWatermark: false) }

        var coverage = 0.0
        var lines = 0
        var counts: [String: Int] = [:]
        var keywordHit = false
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.4 else { continue }
            let box = observation.boundingBox
            coverage += Double(box.width * box.height)
            lines += 1
            let text = candidate.string.lowercased()
            if watermarkKeywords.contains(where: { text.contains($0) }) { keywordHit = true }
            let key = text.filter { $0.isLetter || $0.isNumber }
            if key.count >= 4 { counts[key, default: 0] += 1 }
        }
        coverage = min(coverage, 1)
        let tiled = counts.values.contains { $0 >= 3 }       // same mark repeated across the picture
        let heavy = coverage > textCoverageThreshold || lines >= textLineThreshold
        return TextOverlay(coverage: coverage, isWatermark: keywordHit || tiled || heavy)
    }

    // MARK: Sensitive content (iOS 17 SensitiveContentAnalysis)

    /// Needs the `com.apple.developer.sensitivecontentanalysis.client` entitlement and the user's
    /// "Sensitive Content Warning" setting; otherwise the policy is `.disabled` and we skip the check.
    static func isSensitive(_ image: CGImage) async -> Bool {
        let analyzer = SCSensitivityAnalyzer()
        guard analyzer.analysisPolicy != .disabled else { return false }
        do {
            let analysis = try await analyzer.analyzeImage(image)
            return analysis.isSensitive
        } catch {
            return false
        }
    }
}

// MARK: - Grayscale buffer (blur + perceptual hash)

/// 8-bit grayscale copy of an image, at most `maxSide` px on its longest side.
struct SellGrayImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(cgImage: CGImage, maxSide: Int) {
        let scale = min(1, Double(maxSide) / Double(max(cgImage.width, cgImage.height)))
        let w = max(9, Int(Double(cgImage.width) * scale))
        let h = max(9, Int(Double(cgImage.height) * scale))
        var buffer = [UInt8](repeating: 0, count: w * h)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w; height = h; pixels = buffer
    }

    /// Variance of the 4-neighbour Laplacian, computed per tile on a 4×4 grid; returns the sharpest tile.
    func maxTileLaplacianVariance(grid: Int = 4) -> Double {
        guard width > 4, height > 4 else { return 0 }
        var sums = [Double](repeating: 0, count: grid * grid)
        var squares = [Double](repeating: 0, count: grid * grid)
        var counts = [Int](repeating: 0, count: grid * grid)
        pixels.withUnsafeBufferPointer { p in
            for y in 1..<(height - 1) {
                let ty = min(grid - 1, y * grid / height)
                let row = y * width
                for x in 1..<(width - 1) {
                    let i = row + x
                    let lap = 4 * Int(p[i]) - Int(p[i - 1]) - Int(p[i + 1]) - Int(p[i - width]) - Int(p[i + width])
                    let tile = ty * grid + min(grid - 1, x * grid / width)
                    let v = Double(lap)
                    sums[tile] += v
                    squares[tile] += v * v
                    counts[tile] += 1
                }
            }
        }
        var best = 0.0
        for t in 0..<(grid * grid) where counts[t] > 0 {
            let n = Double(counts[t])
            let mean = sums[t] / n
            best = max(best, squares[t] / n - mean * mean)
        }
        return best
    }

    /// dHash: 9×8 box-averaged thumbnail, one bit per horizontal gradient sign.
    func differenceHash() -> UInt64 {
        let cols = 9, rows = 8
        var cells = [Double](repeating: 0, count: cols * rows)
        for r in 0..<rows {
            let y0 = r * height / rows, y1 = max(y0 + 1, (r + 1) * height / rows)
            for c in 0..<cols {
                let x0 = c * width / cols, x1 = max(x0 + 1, (c + 1) * width / cols)
                var total = 0
                for y in y0..<min(y1, height) {
                    let row = y * width
                    for x in x0..<min(x1, width) { total += Int(pixels[row + x]) }
                }
                cells[r * cols + c] = Double(total) / Double(max(1, (y1 - y0) * (x1 - x0)))
            }
        }
        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for r in 0..<rows {
            for c in 0..<(cols - 1) {
                if cells[r * cols + c] < cells[r * cols + c + 1] { hash |= (1 << bit) }
                bit += 1
            }
        }
        return hash
    }
}
