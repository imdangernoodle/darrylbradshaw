import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders a string (typically a `glassssh://` URL) as a crisp, tintable QR code
/// using CoreImage's `qrCodeGenerator`. The generated image is intentionally
/// drawn with no interpolation so it stays sharp at any size, and is recolored to
/// blend with the Liquid Glass aesthetic.
struct QRCodeView: View {
    private let payload: String
    private var tint: Color
    private var background: Color

    /// Renders the given URL's `absoluteString` as a QR code.
    init(url: URL, tint: Color = .primary, background: Color = .clear) {
        self.payload = url.absoluteString
        self.tint = tint
        self.background = background
    }

    /// Renders an arbitrary string as a QR code.
    init(string: String, tint: Color = .primary, background: Color = .clear) {
        self.payload = string
        self.tint = tint
        self.background = background
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                background
                if let image = Self.makeImage(from: payload) {
                    image
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(tint)
                } else {
                    // Encoding can fail if the payload exceeds the symbol's
                    // capacity; surface a recognizable placeholder rather than
                    // an empty frame.
                    Image(systemName: "qrcode")
                        .resizable()
                        .scaledToFit()
                        .padding(side * 0.2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("QR code")
    }

    /// Shared CoreImage context — reused across renders to avoid the per-call
    /// allocation cost of a fresh `CIContext`.
    private static let context = CIContext()

    /// Generates a black-on-transparent template image. The black pixels are
    /// turned into a template so SwiftUI's `foregroundStyle` can tint them.
    private static func makeImage(from string: String) -> Image? {
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        // High error correction keeps the code scannable even when tinted or
        // partially obscured by the glass overlay.
        filter.correctionLevel = "H"

        guard let output = filter.outputImage else { return nil }

        // The generator emits black data modules on a white background.
        // `CIMaskToAlpha` keeps white as opaque and makes black transparent, so
        // invert first — that turns the data modules white (→ opaque) and the
        // background black (→ transparent). The result is a template whose
        // visible pixels are exactly the data modules and so respects the tint.
        let inverted = output.applyingFilter("CIColorInvert")
        let masked = inverted.applyingFilter("CIMaskToAlpha")
        guard let cgImage = context.createCGImage(masked, from: masked.extent) else { return nil }

        return Image(decorative: cgImage, scale: 1, orientation: .up)
            .renderingMode(.template)
    }
}

#Preview {
    let url = URL(string: "glassssh://connect?host=example.com&port=22&user=alice&name=Example")!
    return VStack(spacing: 24) {
        QRCodeView(url: url)
            .frame(width: 200, height: 200)

        QRCodeView(string: "glassssh://pair?host=10.0.0.5&service=studio&fp=SHA256:abc&token=xyz",
                   tint: .accentColor)
            .frame(width: 200, height: 200)
    }
    .padding()
}
