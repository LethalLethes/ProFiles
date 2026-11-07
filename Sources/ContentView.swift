import SwiftUI
import UniformTypeIdentifiers

private enum ProFilesTab: String, CaseIterable {
    case airlift = "Airlift"
    case afc = "AFC"
    case coreMedia = "CoreMedia"
    case wallet = "Wallet"

    var symbol: String {
        switch self {
        case .airlift: return "arrow.triangle.branch"
        case .afc: return "folder"
        case .coreMedia: return "waveform"
        case .wallet: return "wallet.pass"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: ProFilesTab = .afc

    var body: some View {
        TabView(selection: $selectedTab) {
            AirliftExplorerView()
                .tabItem { Label("Airlift", systemImage: ProFilesTab.airlift.symbol) }
                .tag(ProFilesTab.airlift)

            AFCExplorerView()
                .tabItem { Label("AFC", systemImage: ProFilesTab.afc.symbol) }
                .tag(ProFilesTab.afc)

            CoreMediaLabView()
                .tabItem { Label("CoreMedia", systemImage: ProFilesTab.coreMedia.symbol) }
                .tag(ProFilesTab.coreMedia)

            WalletCardsView()
                .tabItem { Label("Wallet", systemImage: ProFilesTab.wallet.symbol) }
                .tag(ProFilesTab.wallet)
        }
        .tint(.cyan)
    }
}

private struct ModuleHeader: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.cyan)
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }
}

private struct StatusCard: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PairingDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let plistType = UTType(filenameExtension: "plist") ?? .propertyList
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [plistType, .data],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

private struct PairingFileStore {
    static var destinationURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProFiles-Pairing.plist")
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: destinationURL.path)
    }

    static func importFile(from sourceURL: URL) throws {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: sourceURL)
        guard !data.isEmpty else {
            throw NSError(
                domain: "ProFiles.Pairing",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Pairing faylı boşdur."]
            )
        }

        // Validate that the selected file is a readable plist before saving it.
        _ = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )

        try data.write(to: destinationURL, options: .atomic)
    }

    static func remove() throws {
        if exists {
            try FileManager.default.removeItem(at: destinationURL)
        }
    }
}

private struct AirliftExplorerView: View {
    @State private var showingReportPicker = false
    @State private var reportName = "Hesabat seçilməyib"
    @State private var reportSummary = "Airlift nəticə hesabatını JSON və ya mətn faylı kimi import edə bilərsən."
    @State private var reportLoaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ModuleHeader(
                        title: "Airlift Explorer",
                        subtitle: "Airlift testlərinin nəticə və canary hesabatları.",
                        symbol: "arrow.triangle.branch"
                    )
                    StatusCard(
                        title: reportLoaded ? "Hesabat yükləndi" : "Hesabat gözlənilir",
                        detail: reportSummary,
                        symbol: reportLoaded ? "checkmark.circle.fill" : "doc.text.magnifyingglass"
                    )
                    Text(reportName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        showingReportPicker = true
                    } label: {
                        Label("Airlift hesabatını import et", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    StatusCard(
                        title: "Exploit avtomatik başladılmır",
                        detail: "Bu bölmə yalnız sənin təqdim etdiyin test hesabatını oxuyur. Canary nəticəsi exploit-in ümumi sistem fayllarına giriş verdiyini sübut etmir.",
                        symbol: "lock.shield"
                    )
                }
                .padding()
            }
            .navigationTitle("Airlift")
            .sheet(isPresented: $showingReportPicker) {
                PairingDocumentPicker(
                    onPick: { url in
                        do {
                            let data = try readScopedData(from: url)
                            let text = String(data: data, encoding: .utf8) ?? "Mətn formatında olmayan hesabat."
                            reportName = url.lastPathComponent
                            reportSummary = "Fayl: \(data.count) bayt. " + String(text.prefix(500))
                            reportLoaded = true
                        } catch {
                            reportSummary = "Hesabat oxunmadı: \(error.localizedDescription)"
                            reportLoaded = false
                        }
                        showingReportPicker = false
                    },
                    onCancel: { showingReportPicker = false }
                )
                .ignoresSafeArea()
            }
        }
    }
}

private func readScopedData(from url: URL) throws -> Data {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    return try Data(contentsOf: url)
}

private struct AFCExplorerView: View {
    @State private var showingPicker = false
    @State private var pairingReady = PairingFileStore.exists
    @State private var statusMessage = PairingFileStore.exists
        ? "Pairing faylı tətbiqdə saxlanılıb."
        : "Pairing faylı hələ seçilməyib."
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ModuleHeader(
                        title: "AFC Explorer",
                        subtitle: "Paired AFC xidmətinin təqdim etdiyi qovluqlar və fayllar.",
                        symbol: "folder"
                    )

                    StatusCard(
                        title: pairingReady ? "Pairing faylı hazırdır" : "Pairing faylı tələb olunur",
                        detail: statusMessage,
                        symbol: pairingReady ? "checkmark.circle.fill" : "doc.badge.plus"
                    )

                    NavigationLink {
                        AFCFileManagerView()
                    } label: {
                        Label("Cihaz fayllarını aç", systemImage: "externaldrive")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showingPicker = true
                    } label: {
                        Label(
                            pairingReady ? "Pairing faylını dəyiş" : "Pairing faylı seç",
                            systemImage: "doc.badge.plus"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if pairingReady {
                        Button(role: .destructive) {
                            do {
                                try PairingFileStore.remove()
                                pairingReady = false
                                statusMessage = "Pairing faylı tətbiqdən silindi."
                            } catch {
                                statusMessage = error.localizedDescription
                                showingError = true
                            }
                        } label: {
                            Label("Pairing faylını sil", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    StatusCard(
                        title: "LocalDev VPN",
                        detail: "VPN-i iOS Settings-dən aktiv saxla. Bu ekran VPN statusunu birbaşa oxumur.",
                        symbol: "network"
                    )

                    StatusCard(
                        title: "AFC bağlantısı",
                        detail: "Pairing faylı tətbiqə təhlükəsiz surətdə köçürülür. Real qovluq siyahısı üçün ProFiles-ə ayrıca AFC Rust adapteri və onun statik kitabxanası əlavə edilməlidir.",
                        symbol: "cable.connector"
                    )
                }
                .padding()
            }
            .navigationTitle("AFC Explorer")
            .sheet(isPresented: $showingPicker) {
                PairingDocumentPicker(
                    onPick: { url in
                        do {
                            try PairingFileStore.importFile(from: url)
                            pairingReady = true
                            statusMessage = "Pairing faylı uğurla import edildi."
                        } catch {
                            statusMessage = "Import xətası: \(error.localizedDescription)"
                            showingError = true
                        }
                        showingPicker = false
                    },
                    onCancel: {
                        statusMessage = "Fayl seçimi ləğv edildi."
                        showingPicker = false
                    }
                )
                .ignoresSafeArea()
            }
            .alert("AFC Explorer", isPresented: $showingError) {
                Button("Bağla", role: .cancel) { }
            } message: {
                Text(statusMessage)
            }
        }
    }
}

private struct CoreMediaLabView: View {
    @State private var showingLogPicker = false
    @State private var logName = "Crash log seçilməyib"
    @State private var logSummary = "CoreMedia və ya panic log faylını seçərək diaqnostika edə bilərsən."
    @State private var logLoaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ModuleHeader(
                        title: "CoreMedia Lab",
                        subtitle: "Cihaz məlumatı və crash/panic log diaqnostikası.",
                        symbol: "waveform"
                    )
                    StatusCard(
                        title: "Cihaz",
                        detail: "Model: \(UIDevice.current.model)\n iOS: \(UIDevice.current.systemVersion)",
                        symbol: "iphone"
                    )
                    StatusCard(
                        title: logLoaded ? "Log yükləndi" : "Log gözlənilir",
                        detail: logSummary,
                        symbol: logLoaded ? "checkmark.circle.fill" : "doc.text.magnifyingglass"
                    )
                    Text(logName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        showingLogPicker = true
                    } label: {
                        Label("Crash / panic log seç", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    StatusCard(
                        title: "Təhlükəsiz analiz",
                        detail: "Log faylı yalnız oxunur. CoreMedia PoC avtomatik işə salınmır və bu modul fayl sistemi icazəsi yaratmır.",
                        symbol: "lock.shield"
                    )
                }
                .padding()
            }
            .navigationTitle("CoreMedia Lab")
            .sheet(isPresented: $showingLogPicker) {
                PairingDocumentPicker(
                    onPick: { url in
                        do {
                            let data = try readScopedData(from: url)
                            let content = String(data: data, encoding: .utf8) ?? "Log UTF-8 mətn deyil."
                            let lines = content.components(separatedBy: .newlines)
                            let preview = lines.prefix(8).joined(separator: "\n")
                            logName = url.lastPathComponent
                            logSummary = "Ölçü: \(data.count) bayt.\n\(preview.prefix(700))"
                            logLoaded = true
                        } catch {
                            logSummary = "Log oxunmadı: \(error.localizedDescription)"
                            logLoaded = false
                        }
                        showingLogPicker = false
                    },
                    onCancel: { showingLogPicker = false }
                )
                .ignoresSafeArea()
            }
        }
    }
}
