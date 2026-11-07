import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AirliftFFI

private struct WalletCard: Identifiable {
    let id: String
    var image: UIImage?
    var isSelected: Bool = true
    var displayName: String { "Wallet Card · \(id.prefix(8))…" }
    var imageURL: URL { WalletCardStore.imageURL(for: id) }
}

private enum WalletCardStore {
    static var pairingPath: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProFiles-Pairing.plist").path
    }

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WalletSkins", isDirectory: true)
    }

    static func imageURL(for id: String) -> URL {
        let safe = id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent("card_\(safe).png")
    }

    static func loadIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: "profiles.wallet.cardIDs") ?? []
    }

    static func saveIDs(_ ids: [String]) {
        UserDefaults.standard.set(Array(NSOrderedSet(array: ids)) as? [String] ?? ids,
                                  forKey: "profiles.wallet.cardIDs")
    }
}

@MainActor
private final class WalletCardsModel: ObservableObject {
    @Published var cards: [WalletCard] = []
    @Published var isScanning = false
    @Published var status = "Pairing faylını yoxla, sonra Scan düyməsinə bas."
    @Published var error: String?
    @Published var isApplying = false
    @Published var progress = 0.0

    private var scanThread: Thread?

    init() {
        try? FileManager.default.createDirectory(at: WalletCardStore.directory,
                                                  withIntermediateDirectories: true)
        cards = WalletCardStore.loadIDs().map { id in
            WalletCard(id: id, image: UIImage(contentsOfFile: WalletCardStore.imageURL(for: id).path))
        }
    }

    func toggleScan() {
        if isScanning {
            al_syslog_stream_stop()
            isScanning = false
            status = "Axtarış dayandırıldı. Tapılan kart: \(cards.count)"
            return
        }
        guard FileManager.default.fileExists(atPath: WalletCardStore.pairingPath) else {
            error = "Əvvəlcə AFC bölməsində Pairing .plist faylını import et."
            return
        }
        isScanning = true
        status = "Apple Pay-i aç və kartına toxun…"
        let path = WalletCardStore.pairingPath
        scanThread = Thread { [weak self] in
            var outError: UnsafeMutablePointer<CChar>?
            let rc = path.withCString { pairing in
                al_syslog_stream_start(pairing, { _, line in
                    guard let line else { return }
                    let text = String(cString: line)
                    DispatchQueue.main.async { self?.consume(text) }
                }, nil, &outError)
            }
            let message = outError.map { String(cString: $0) }
            if let outError { al_string_free(outError) }
            DispatchQueue.main.async {
                self?.isScanning = false
                if rc != 0 { self?.error = message ?? "Wallet scan xətası: \(rc)" }
            }
        }
        scanThread?.name = "ProFiles.WalletScanner"
        scanThread?.qualityOfService = .userInitiated
        scanThread?.start()
    }

    private func consume(_ line: String) {
        let lower = line.lowercased()
        guard lower.contains("wallet") || lower.contains("pass") ||
              lower.contains("card") || lower.contains("stockholm") ||
              lower.contains("activation") || lower.contains("nfcd") else { return }
        let patterns = [
            #"/(?:Cards|Passes/Cards)/([-A-Za-z0-9_+=]{20,64})(?=[/\s\"'\),]|$)"#,
            #"/([-A-Za-z0-9_+=]{20,64})\.(?:pkpass|cache|pkcache)(?=[/\s\"'\),]|$)"#,
            #"PDCardFileManager:\s*writing card\s+([-A-Za-z0-9_+=]{20,64})"#,
            #"PDPassLibrary:\s*wrote pass\s+([-A-Za-z0-9_+=]{20,64})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(line.startIndex..., in: line)
            for match in regex.matches(in: line, range: range) {
                guard let r = Range(match.range(at: 1), in: line) else { continue }
                let id = String(line[r])
                guard !id.contains("/"), !cards.contains(where: { $0.id == id }) else { continue }
                cards.append(WalletCard(id: id))
                WalletCardStore.saveIDs(cards.map(\.id))
                status = "Yeni kart aşkarlandı: \(id.prefix(8))…"
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    func saveArtwork(_ image: UIImage, for id: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let normalized = WalletArtwork.render(image, size: CGSize(width: 1536, height: 969))
        cards[index].image = normalized
        try? FileManager.default.createDirectory(at: WalletCardStore.directory,
                                                  withIntermediateDirectories: true)
        if let data = normalized.pngData() {
            try? data.write(to: WalletCardStore.imageURL(for: id), options: .atomic)
        }
    }

    func applySelected() {
        let selected = cards.filter { $0.isSelected && $0.image != nil }
        guard !selected.isEmpty else {
            error = "Əvvəlcə kart seç və onun üçün şəkil əlavə et."
            return
        }
        guard FileManager.default.fileExists(atPath: WalletCardStore.pairingPath) else {
            error = "Pairing .plist faylı tapılmadı."
            return
        }
        isApplying = true
        progress = 0
        let pairing = WalletCardStore.pairingPath
        Task.detached(priority: .userInitiated) { [weak self] in
            var successes = 0
            for (index, card) in selected.enumerated() {
                guard let image = card.image else { continue }
                let stage = FileManager.default.temporaryDirectory
                    .appendingPathComponent("profiles-wallet-\(UUID().uuidString)", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
                    let assets = WalletArtwork.assets(from: image)
                    for (name, data) in assets {
                        try data.write(to: stage.appendingPathComponent(name), options: .atomic)
                    }
                    let target = "/var/mobile/Library/Passes/Cards/\(card.id).pkpass"
                    var errorPointer: UnsafeMutablePointer<CChar>?
                    let rc = pairing.withCString { p in
                        stage.path.withCString { s in
                            target.withCString { t in
                                al_exploit_write_dir(p, s, t, nil, nil, &errorPointer)
                            }
                        }
                    }
                    let message = errorPointer.map { String(cString: $0) }
                    if let errorPointer { al_string_free(errorPointer) }
                    if rc == 0 {
                        successes += 1
                        // Best-effort invalidation of the per-card artwork caches.
                        let invalidation = FileManager.default.temporaryDirectory
                            .appendingPathComponent("profiles-wallet-cache-\(UUID().uuidString)", isDirectory: true)
                        try? FileManager.default.createDirectory(at: invalidation, withIntermediateDirectories: true)
                        for leaf in ["FrontFace", "Preview", "PlaceHolder"] {
                            try? Data("corrupted".utf8).write(to: invalidation.appendingPathComponent(leaf))
                        }
                        for ext in [".cache", ".pkcache"] {
                            var ignored: UnsafeMutablePointer<CChar>?
                            _ = pairing.withCString { p in
                                invalidation.path.withCString { s in
                                    ("/var/mobile/Library/Passes/Cards/\(card.id)\(ext)").withCString { t in
                                        al_exploit_write_dir(p, s, t, nil, nil, &ignored)
                                    }
                                }
                            }
                            if let ignored { al_string_free(ignored) }
                        }
                        try? FileManager.default.removeItem(at: invalidation)
                    } else {
                        await MainActor.run { self?.error = message ?? "Kart tətbiq edilə bilmədi (\(rc))." }
                    }
                    try? FileManager.default.removeItem(at: stage)
                } catch {
                    await MainActor.run { self?.error = error.localizedDescription }
                }
                await MainActor.run { self?.progress = Double(index + 1) / Double(selected.count) }
            }
            await MainActor.run {
                self?.isApplying = false
                self?.status = "\(successes)/\(selected.count) kart üçün dizayn tətbiq edildi. Wallet-i tam bağlayıb yenidən aç."
            }
        }
    }

    func removeCard(_ id: String) {
        cards.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: WalletCardStore.imageURL(for: id))
        WalletCardStore.saveIDs(cards.map(\.id))
    }
}

private enum WalletArtwork {
    static func render(_ image: UIImage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let w = image.size.width * scale
            let h = image.size.height * scale
            image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        }
    }

    static func assets(from image: UIImage) -> [String: Data] {
        let normalized = render(image, size: CGSize(width: 1536, height: 969))
        let twoX = render(normalized, size: CGSize(width: 1024, height: 646))
        var result: [String: Data] = [:]
        if let d = normalized.pngData() {
            for name in ["cardBackgroundCombined@3x.png", "diffuse@3x.png", "background@3x.png", "strip@3x.png"] { result[name] = d }
        }
        if let d = twoX.pngData() {
            for name in ["cardBackgroundCombined@2x.png", "diffuse@2x.png", "background@2x.png", "strip@2x.png"] { result[name] = d }
        }
        let bounds = CGRect(origin: .zero, size: CGSize(width: 1536, height: 969))
        let pdf = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            normalized.draw(in: bounds)
        }
        result["cardBackgroundCombined.pdf"] = pdf
        result["background.pdf"] = pdf
        result["strip.pdf"] = pdf
        return result
    }
}

struct WalletCardsView: View {
    @StateObject private var model = WalletCardsModel()
    @State private var importingFor: String?
    @State private var editingCard: String?
    @State private var pendingImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Apple Wallet kart dizaynı", systemImage: "wallet.pass")
                        .font(.title2.bold())
                    Text("Kartı aşkar et, şəkil seç, görünüşünü tənzimlə və Wallet-ə tətbiq et.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button { model.toggleScan() } label: {
                        Label(model.isScanning ? "Axtarışı dayandır" : "Wallet kartlarını aşkar et",
                              systemImage: model.isScanning ? "stop.circle.fill" : "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                    Text(model.status).font(.footnote).foregroundStyle(.secondary)
                }.padding(.horizontal)

                if model.cards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "creditcard").font(.system(size: 42)).foregroundStyle(.secondary)
                        Text("Kart tapılmayıb").font(.headline)
                        Text("Scan düyməsinə bas, sonra Apple Pay-də kartını aç.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
                } else {
                    List {
                        ForEach(model.cards) { card in
                            HStack(spacing: 12) {
                                if let image = card.image {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(width: 92, height: 58).clipShape(RoundedRectangle(cornerRadius: 9))
                                } else {
                                    RoundedRectangle(cornerRadius: 9).fill(.quaternary)
                                        .frame(width: 92, height: 58)
                                        .overlay(Image(systemName: "creditcard").font(.title2))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(card.displayName).font(.subheadline.bold())
                                    Text(card.image == nil ? "Dizayn seçilməyib" : "Dizayn hazırdır")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    Button("Şəkil seç və redaktə et", systemImage: "photo") { importingFor = card.id }
                                    Button("Kartı siyahıdan sil", systemImage: "trash", role: .destructive) { model.removeCard(card.id) }
                                } label: { Image(systemName: "ellipsis.circle").font(.title2) }
                            }.padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                }

                if model.isApplying {
                    VStack(spacing: 6) {
                        ProgressView(value: model.progress)
                        Text("Wallet dizaynı tətbiq olunur…").font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal)
                }
                Button { model.applySelected() } label: {
                    Label("Dizaynları Wallet-ə tətbiq et", systemImage: "paintbrush.pointed.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isApplying || !model.cards.contains(where: { $0.image != nil }))
                .padding(.horizontal)
            }
            .navigationTitle("Apple Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: Binding(get: { importingFor != nil }, set: { if !$0 { importingFor = nil } }),
                          allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard let image = UIImage(data: try Data(contentsOf: url)) else {
                        model.error = "Şəkil açıla bilmədi."; return
                    }
                    pendingImage = image
                    editingCard = importingFor
                } catch { model.error = error.localizedDescription }
                importingFor = nil
            }
            .sheet(isPresented: Binding(get: { pendingImage != nil && editingCard != nil },
                                        set: { if !$0 { pendingImage = nil; editingCard = nil } })) {
                if let image = pendingImage, let id = editingCard {
                    WalletArtworkEditor(image: image) { finalImage in
                        model.saveArtwork(finalImage, for: id)
                        pendingImage = nil
                        editingCard = nil
                    }
                }
            }
            .alert("Apple Wallet", isPresented: Binding(get: { model.error != nil },
                                                         set: { if !$0 { model.error = nil } })) {
                Button("Bağla", role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
        }
    }
}

private struct WalletArtworkEditor: View {
    let image: UIImage
    let onSave: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: Double = 1
    @State private var zoomStart: Double = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Şəkli kartın üzərində sürüşdür və iki barmaqla böyüt.")
                    .font(.subheadline).foregroundStyle(.secondary)
                GeometryReader { geo in
                    let size = geo.size
                    let base = max(size.width / image.size.width, size.height / image.size.height)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: image.size.width * base, height: image.size.height * base)
                        .scaleEffect(CGFloat(zoom))
                        .offset(offset)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .gesture(DragGesture().onChanged { value in
                            offset = CGSize(width: dragStart.width + value.translation.width,
                                            height: dragStart.height + value.translation.height)
                        }.onEnded { _ in dragStart = offset })
                        .simultaneousGesture(MagnificationGesture().onChanged { value in
                            zoom = min(4, max(1, zoomStart * value))
                        }.onEnded { _ in zoomStart = zoom })
                }
                .aspectRatio(1.586, contentMode: .fit)
                .padding(.horizontal)
                Slider(value: $zoom, in: 1...4) { Text("Ölçü") }
                    .padding(.horizontal)
                Button("Mərkəzə qaytar") { zoom = 1; zoomStart = 1; offset = .zero; dragStart = .zero }
                    .buttonStyle(.bordered)
                Spacer(minLength: 0)
            }
            .padding(.top)
            .navigationTitle("Kart görünüşü")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Ləğv et") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Saxla") { onSave(renderFinal()); dismiss() }
                }
            }
        }
    }

    private func renderFinal() -> UIImage {
        let size = CGSize(width: 1536, height: 969)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let base = max(size.width / image.size.width, size.height / image.size.height)
            let w = image.size.width * base * CGFloat(zoom)
            let h = image.size.height * base * CGFloat(zoom)
            let factorX = size.width / max(UIScreen.main.bounds.width - 32, 1)
            let factorY = size.height / max((UIScreen.main.bounds.width - 32) / 1.586, 1)
            let rect = CGRect(x: (size.width - w) / 2 + offset.width * factorX,
                              y: (size.height - h) / 2 + offset.height * factorY,
                              width: w, height: h)
            image.draw(in: rect)
        }
    }
}
