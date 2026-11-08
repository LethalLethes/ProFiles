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
    @Published var applyLog: [String] = []

    func appendApplyLog(_ line: String) {
        applyLog.append(line)
        if applyLog.count > 120 { applyLog.removeFirst(applyLog.count - 120) }
    }

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
        let callbackContext = Unmanaged.passRetained(self).toOpaque()
        let callbackContextAddress = UInt(bitPattern: callbackContext)
        scanThread = Thread {
            let callbackContext = UnsafeMutableRawPointer(bitPattern: callbackContextAddress)!
            var outError: UnsafeMutablePointer<CChar>?
            let rc = path.withCString { pairing in
                al_syslog_stream_start(pairing, { context, line in
                    guard let context, let line else { return }
                    let model = Unmanaged<WalletCardsModel>.fromOpaque(context).takeUnretainedValue()
                    let text = String(cString: line)
                    DispatchQueue.main.async { model.consume(text) }
                }, callbackContext, &outError)
            }
            let message = outError.map { String(cString: $0) }
            if let outError { al_string_free(outError) }
            Unmanaged<WalletCardsModel>.fromOpaque(callbackContext).release()
            DispatchQueue.main.async {
                self.isScanning = false
                if rc != 0 { self.error = message ?? "Wallet scan xətası: \(rc)" }
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
        let normalized = WalletArtwork.prepareCardImage(image)
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
        applyLog.removeAll()
        appendApplyLog("AirCard Wallet skin injection başladılır.")
        let pairing = WalletCardStore.pairingPath
        let model = self

        Task.detached(priority: .userInitiated) {
            var successes = 0
            var failures = 0
            let callbackContext = Unmanaged.passRetained(model).toOpaque()
            defer { Unmanaged<WalletCardsModel>.fromOpaque(callbackContext).release() }

            for (index, card) in selected.enumerated() {
                guard let image = card.image,
                      let cleanID = WalletArtwork.cleanCardID(card.id) else {
                    failures += 1
                    await MainActor.run { model.appendApplyLog("Kart ID və ya şəkil etibarsızdır: \(card.id)") }
                    continue
                }

                let stage = FileManager.default.temporaryDirectory
                    .appendingPathComponent("profiles-wallet-\(UUID().uuidString)", isDirectory: true)

                do {
                    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
                    let assets = WalletArtwork.assets(from: image)
                    guard !assets.isEmpty else {
                        throw NSError(domain: "ProFiles.Wallet", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Wallet artwork faylları yaradıla bilmədi."])
                    }
                    for (name, data) in assets {
                        try data.write(to: stage.appendingPathComponent(name), options: .atomic)
                    }

                    let target = "/var/mobile/Library/Passes/Cards/\(cleanID).pkpass"
                    await MainActor.run {
                        model.appendApplyLog("[\(index + 1)/\(selected.count)] \(cleanID.prefix(12))… kartına yazılır.")
                    }

                    var errorPointer: UnsafeMutablePointer<CChar>?
                    let rc = pairing.withCString { pairC in
                        stage.path.withCString { sourceC in
                            target.withCString { targetC in
                                al_exploit_write_dir(pairC, sourceC, targetC, { context, message in
                                    guard let context, let message else { return }
                                    let sink = Unmanaged<WalletCardsModel>.fromOpaque(context).takeUnretainedValue()
                                    let line = String(cString: message)
                                    DispatchQueue.main.async { sink.appendApplyLog(line) }
                                }, callbackContext, &errorPointer)
                            }
                        }
                    }

                    let message = errorPointer.map { String(cString: $0) }
                    if let errorPointer { al_string_free(errorPointer) }

                    guard rc == 0 else {
                        failures += 1
                        await MainActor.run {
                            model.appendApplyLog("FFI yazma xətası (\(rc)): \(message ?? "səbəb göstərilmədi")")
                            model.error = "Kart şəkli yazılmadı: \(message ?? "FFI error \(rc)")"
                        }
                        try? FileManager.default.removeItem(at: stage)
                        continue
                    }

                    await MainActor.run { model.appendApplyLog("Kart faylları yazıldı. Cache yenilənir…") }

                    // Same cache invalidation sequence used by AirCard.
                    let invalidation = FileManager.default.temporaryDirectory
                        .appendingPathComponent("profiles-wallet-cache-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: invalidation, withIntermediateDirectories: true)
                    for leaf in ["FrontFace", "Preview", "PlaceHolder"] {
                        try Data("corrupted".utf8).write(to: invalidation.appendingPathComponent(leaf), options: .atomic)
                    }

                    for ext in [".cache", ".pkcache"] {
                        var ignored: UnsafeMutablePointer<CChar>?
                        _ = pairing.withCString { pairC in
                            invalidation.path.withCString { sourceC in
                                ("/var/mobile/Library/Passes/Cards/\(cleanID)\(ext)").withCString { targetC in
                                    al_exploit_write_dir(pairC, sourceC, targetC, nil, nil, &ignored)
                                }
                            }
                        }
                        if let ignored { al_string_free(ignored) }
                    }

                    try? FileManager.default.removeItem(at: invalidation)
                    try? FileManager.default.removeItem(at: stage)
                    successes += 1
                    await MainActor.run { model.appendApplyLog("Skin yazıldı: \(cleanID.prefix(12))…") }
                } catch {
                    failures += 1
                    try? FileManager.default.removeItem(at: stage)
                    await MainActor.run {
                        model.appendApplyLog("Xəta: \(error.localizedDescription)")
                        model.error = error.localizedDescription
                    }
                }

                await MainActor.run { model.progress = Double(index + 1) / Double(selected.count) }
            }

            let successCount = successes
            let failureCount = failures
            let totalCount = selected.count
            await MainActor.run {
                model.isApplying = false
                model.status = "\(successCount)/\(totalCount) kart üçün skin yazıldı; \(failureCount) xəta. Wallet-i tam bağla və yenidən aç."
                model.appendApplyLog("Yekun: \(successCount) uğurlu, \(failureCount) uğursuz.")
            }
        }
    }

    @discardableResult
    func addCardsManually(_ raw: String) -> Int {
        let parts = raw.components(separatedBy: CharacterSet(charactersIn: " \n\r\t,;"))
        var added = 0
        for part in parts {
            guard let cleanID = WalletArtwork.cleanCardID(part),
                  !cards.contains(where: { $0.id == cleanID }) else { continue }
            cards.append(WalletCard(id: cleanID))
            added += 1
        }
        if added > 0 {
            WalletCardStore.saveIDs(cards.map(\.id))
            status = "\(added) kart ID-si manual əlavə edildi."
        }
        return added
    }

    func removeCard(_ id: String) {
        cards.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: WalletCardStore.imageURL(for: id))
        WalletCardStore.saveIDs(cards.map(\.id))
    }
}

private enum WalletArtwork {
    static let placeholderIDs: Set<String> = [
        "OM6NYhwXMZrAw0sRUjR62wmF4ZQ=",
        "M6nDwZrkYbFlsodLgCbvyFZQ1cc=",
        "kJL-D0rr-SZhbj2c8nK-OQ9hCMY=",
        "hwAtAmHKYwsQrJbT5cTNDsaxVME="
    ]

    static func cleanCardID(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "'\",()<>;[]{}"))
        if value.contains("/") { value = (value as NSString).lastPathComponent }
        for ext in [".pkpass", ".cache", ".pkcache"] where value.hasSuffix(ext) {
            value = String(value.dropLast(ext.count))
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "'\",()<>;[]{}. "))
        guard (20...64).contains(value.count), !value.contains("/") else { return nil }
        if value.count == 36 && value.filter({ $0 == "-" }).count == 4 { return nil }
        return value
    }

    static func prepareCardImage(_ image: UIImage) -> UIImage {
        let normalized = normalizeAndDownsample(image, maxDimension: 2560)
        return resize(normalized, targetSize: CGSize(width: 1536, height: 969))
    }

    static func normalizeAndDownsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let target = CGSize(width: max(1, floor(size.width * scale)),
                            height: max(1, floor(size.height * scale)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static func resize(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return image }
        let scale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (targetSize.width - scaled.width) / 2,
                             y: (targetSize.height - scaled.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let result = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: scaled))
        }
        return result
    }

    static func assets(from image: UIImage) -> [String: Data] {
        let normalized = normalizeAndDownsample(image, maxDimension: 2560)
        let bg3x = resize(normalized, targetSize: CGSize(width: 1536, height: 969))
        let bg2x = resize(normalized, targetSize: CGSize(width: 1024, height: 646))
        var skins: [String: Data] = [:]

        if let data3x = bg3x.pngData() {
            skins["cardBackgroundCombined@3x.png"] = data3x
            skins["diffuse@3x.png"] = data3x
            skins["background@3x.png"] = data3x
            skins["strip@3x.png"] = data3x
        }
        if let data2x = bg2x.pngData() {
            skins["cardBackgroundCombined@2x.png"] = data2x
            skins["diffuse@2x.png"] = data2x
            skins["background@2x.png"] = data2x
            skins["strip@2x.png"] = data2x
        }

        let pdfBounds = CGRect(origin: .zero, size: CGSize(width: 1536, height: 969))
        let pdf = UIGraphicsPDFRenderer(bounds: pdfBounds).pdfData { context in
            context.beginPage()
            normalized.draw(in: pdfBounds)
        }
        skins["cardBackgroundCombined.pdf"] = pdf
        skins["background.pdf"] = pdf
        skins["strip.pdf"] = pdf
        return skins
    }
}

struct WalletCardsView: View {
    @StateObject private var model = WalletCardsModel()
    @State private var importingFor: String?
    @State private var editingCard: String?
    @State private var pendingImage: UIImage?
    @State private var showManualAdd = false
    @State private var manualCardIDs = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Apple Wallet kart dizaynı", systemImage: "wallet.pass")
                        .font(.title2.bold())
                    Text("Kartı aşkar et, şəkil seç, görünüşünü tənzimlə və Wallet-ə tətbiq et.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button { model.toggleScan() } label: {
                            Label(model.isScanning ? "Dayandır" : "Kartları aşkar et",
                                  systemImage: model.isScanning ? "stop.circle.fill" : "dot.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Button { showManualAdd = true } label: {
                            Label("Manual əlavə et", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }
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

                if model.isApplying || !model.applyLog.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if model.isApplying { ProgressView(value: model.progress) }
                        Text(model.isApplying ? "Wallet dizaynı tətbiq olunur…" : model.status)
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(model.applyLog.suffix(5).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary).lineLimit(2)
                        }
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
            .sheet(isPresented: $showManualAdd) {
                NavigationStack {
                    Form {
                        Section("AirCard Card Hash / Token") {
                            TextField("Kart hash/token-ini yapışdır", text: $manualCardIDs, axis: .vertical)
                                .font(.system(.body, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .lineLimit(3...7)
                        }
                        Section {
                            Text("AirCard-da Manual Add bölməsindəki kart hash-ini buraya yapışdır. Bir neçə ID-ni boşluq, vergül və ya yeni sətirlə ayıra bilərsən. Bank kartının nömrəsini, CVV-ni və ya Apple Pay ödəniş tokenini daxil etmə.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Kartı manual əlavə et")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Ləğv et") { showManualAdd = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Əlavə et") {
                                let added = model.addCardsManually(manualCardIDs)
                                if added == 0 {
                                    model.error = "Etibarlı yeni kart hash-i tapılmadı. AirCard-dan tam hash-i köçür."
                                }
                                manualCardIDs = ""
                                showManualAdd = false
                            }
                            .disabled(manualCardIDs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
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
