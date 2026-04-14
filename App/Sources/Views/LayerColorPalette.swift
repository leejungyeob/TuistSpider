import SwiftUI

enum LayerColorPalette {
    static func color(for layerName: String?, isExternal: Bool = false) -> Color {
        if isExternal {
            return .orange
        }

        guard let layerName else {
            return Color.gray
        }

        let hash = stableHash(for: layerName)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.58, brightness: 0.82)
    }

    private static func stableHash(for value: String) -> UInt32 {
        value.unicodeScalars.reduce(UInt32(5381)) { partialResult, scalar in
            ((partialResult << 5) &+ partialResult) &+ UInt32(scalar.value)
        }
    }
}
