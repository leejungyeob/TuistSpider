import AppKit
import SwiftUI

enum GraphPNGExportServiceError: LocalizedError {
    case invalidSize
    case bitmapCreationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidSize:
            return "저장할 PNG 크기가 올바르지 않습니다."
        case .bitmapCreationFailed:
            return "비트맵 이미지를 만들지 못했습니다."
        case .pngEncodingFailed:
            return "PNG 데이터 인코딩에 실패했습니다."
        }
    }
}

@MainActor
enum GraphPNGExportService {
    static func exportPNG<Content: View>(
        view: Content,
        size: CGSize,
        to fileURL: URL,
        scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2
    ) throws {
        guard size.width > 0, size.height > 0 else {
            throw GraphPNGExportServiceError.invalidSize
        }

        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.appearance = NSApp.effectiveAppearance
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        let pixelWidth = Int((size.width * scale).rounded(.up))
        let pixelHeight = Int((size.height * scale).rounded(.up))
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else {
            throw GraphPNGExportServiceError.bitmapCreationFailed
        }

        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw GraphPNGExportServiceError.pngEncodingFailed
        }

        try pngData.write(to: fileURL, options: .atomic)
    }
}
