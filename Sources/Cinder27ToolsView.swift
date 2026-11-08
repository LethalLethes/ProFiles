import SwiftUI
import UniformTypeIdentifiers
import Foundation
import CoreGraphics
import CoreText
import ImageIO

/// Cinder27-inspired, non-destructive file inspection tools.
/// All parsing is performed only on a file explicitly selected by the user.
struct Cinder27ToolsView: View {
    @State private var showingImporter = false
    @State private var fileName = "Fayl seçilməyib"
    @State private var report = "PDF, şəkil, şrift, Mach-O və mətn faylını seçərək real analiz et."
    @State private var isSuccess = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Cinder27 File Lab", systemImage: "wrench.and.screwdriver")
                            .font(.title2.bold())
                        Text("Cinder27 mənbələrindəki parser yanaşmalarının ProFiles üçün təhlükəsiz, fayl-seçimli inteqrasiyası.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Heç bir exploit, sandbox keçidi, kernel əməliyyatı və ya avtomatik test başladılmır.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Fayl analizi") {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Fayl seç və analiz et", systemImage: "doc.badge.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)

                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(isSuccess ? "Analiz tamamlandı" : "Nəticə", systemImage: isSuccess ? "checkmark.circle.fill" : "info.circle")
                        .font(.headline)
                        .foregroundStyle(isSuccess ? .green : .primary)

                    Text(report)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section("Aktiv analizatorlar") {
                    toolRow("PDF / CoreGraphics", "Səhifə sayı, ölçü və ilk səhifənin raster yoxlaması")
                    toolRow("ImageIO", "Şəkil formatı, ölçülər, frame sayı və thumbnail decode")
                    toolRow("CoreText / FontParser", "Şrift adı, PostScript adı və glyph sayı")
                    toolRow("Mach-O", "Magic, 32/64-bit, CPU tipi və load-command sayı")
                    toolRow("Mətn / HEX", "UTF-8 preview və ilkin baytların HEX görünüşü")
                }

                Section("Məhdudiyyət") {
                    Text("Analiz yalnız Files tətbiqindən sənin seçdiyin fayl üzərində aparılır. Sistem qovluqları və başqa tətbiqlərin sandbox-ları axtarılmır. Zərərli və ya qəsdən pozulmuş fayllar üçün ayrıca izolyasiya təmin edilmir; tanımadığın faylları açma.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cinder27")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.data, .item],
                allowsMultipleSelection: false
            ) { result in
                inspect(result)
            }
        }
    }

    private func toolRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func inspect(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > 128 * 1024 * 1024 {
                throw InspectionError.message("Fayl 128 MB limitini keçir.")
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard !data.isEmpty else {
                throw InspectionError.message("Fayl boşdur.")
            }

            fileName = url.lastPathComponent
            report = try CinderFileInspector.inspect(data, extension: url.pathExtension.lowercased())
            isSuccess = true
        } catch {
            isSuccess = false
            report = "Analiz xətası: \(error.localizedDescription)"
        }
    }
}

private enum InspectionError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(value) = self { return value }
        return "Naməlum analiz xətası."
    }
}

private enum CinderFileInspector {
    static func inspect(_ data: Data, extension ext: String) throws -> String {
        if ext == "pdf" || data.starts(with: Array("%PDF-".utf8)) {
            return try inspectPDF(data)
        }
        if let imageReport = inspectImage(data) {
            return imageReport
        }
        if let fontReport = inspectFont(data) {
            return fontReport
        }
        if let machoReport = inspectMachO(data) {
            return machoReport
        }

        let previewData = data.prefix(160)
        let hex = previewData.map { String(format: "%02X", $0) }.joined(separator: " ")
        if let text = String(data: data.prefix(1200), encoding: .utf8) {
            return "Format: UTF-8 mətn / naməlum\nÖlçü: \(data.count) bayt\n\n\(text)"
        }
        return "Format: tanınmayan binary\nÖlçü: \(data.count) bayt\nİlk \(previewData.count) bayt HEX:\n\(hex)"
    }

    private static func inspectPDF(_ data: Data) throws -> String {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            throw InspectionError.message("PDF parser faylı aça bilmədi.")
        }
        let count = document.numberOfPages
        guard count > 0, let page = document.page(at: 1) else {
            throw InspectionError.message("PDF-də səhifə tapılmadı.")
        }
        let bounds = page.getBoxRect(.mediaBox)
        let side = 256
        let bytesPerRow = side * 4
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw InspectionError.message("PDF bitmap konteksti yaradıla bilmədi.")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.drawPDFPage(page)
        return "Format: PDF\nÖlçü: \(data.count) bayt\nSəhifələr: \(count)\nİlk səhifə: \(Int(bounds.width)) × \(Int(bounds.height)) pt\nRaster yoxlaması: uğurlu (256 × 256)"
    }

    private static func inspectImage(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let type = CGImageSourceGetType(source) as String? ?? "naməlum"
        let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ]
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil
        return "Format: ImageIO / \(type)\nÖlçü: \(data.count) bayt\nÖlçülər: \(width) × \(height) px\nFrame sayı: \(count)\nTam decode: \(decoded ? "uğurlu" : "uğursuz")\nThumbnail: \(thumbnail ? "uğurlu" : "uğursuz")"
    }

    private static func inspectFont(_ data: Data) -> String? {
        guard let provider = CGDataProvider(data: data as CFData),
              let font = CGFont(provider) else { return nil }
        let fullName = font.fullName as String? ?? "naməlum"
        let postScript = font.postScriptName as String? ?? "naməlum"
        return "Format: CoreGraphics / FontParser\nÖlçü: \(data.count) bayt\nAd: \(fullName)\nPostScript: \(postScript)\nGlyph sayı: \(font.numberOfGlyphs)"
    }

    private static func inspectMachO(_ data: Data) -> String? {
        guard data.count >= 28 else { return nil }
        let b = [UInt8](data.prefix(32))
        let magic = b[0...3].map { String(format: "%02X", $0) }.joined(separator: " ")
        let is64 = b[0] == 0xCF && b[1] == 0xFA && b[2] == 0xED && b[3] == 0xFE
        let is32 = b[0] == 0xCE && b[1] == 0xFA && b[2] == 0xED && b[3] == 0xFE
        guard is64 || is32 else { return nil }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(b[offset]) | (UInt32(b[offset + 1]) << 8) |
            (UInt32(b[offset + 2]) << 16) | (UInt32(b[offset + 3]) << 24)
        }
        let cpu = u32(4)
        let fileType = u32(12)
        let commands = u32(16)
        return "Format: Mach-O\nMagic: \(magic)\nÖlçü: \(data.count) bayt\nArxitektura başlığı: \(is64 ? "64-bit" : "32-bit")\nCPU type: 0x\(String(cpu, radix: 16))\nFile type: \(fileType)\nLoad commands: \(commands)"
    }
}
