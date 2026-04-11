// ICD360SVPN — Components/QRCodeView.swift
// MARK: - Local QR code rendering
//
// CoreImage's CIQRCodeGenerator produces a tiny image (one module per
// pixel). We scale it up with CIAffineTransform so the resulting
// NSImage stays sharp at the requested size.
//
// QR generation happens entirely in the app — the agent never sees
// the payload again, and we don't add a server-side image dependency.

import SwiftUI
import CoreImage.CIFilterBuiltins
import AppKit

struct QRCodeView: View {
    let payload: String
    let size: CGFloat

    init(_ payload: String, size: CGFloat = 256) {
        self.payload = payload
        self.size = size
    }

    var body: some View {
        if let nsImage = generate() {
            Image(nsImage: nsImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [4]))
            Text("QR generation failed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
    }

    private func generate() -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Scale up to a meaningful pixel size before rasterising.
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
}

#Preview {
    QRCodeView("hello world", size: 200)
        .padding()
}
