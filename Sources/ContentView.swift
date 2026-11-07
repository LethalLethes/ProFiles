import SwiftUI
import UniformTypeIdentifiers

private enum ProFilesTab: String, CaseIterable {
    case airlift = "Airlift"
    case afc = "AFC"
    case coreMedia = "CoreMedia"

    var symbol: String {
        switch self {
        case .airlift: return "arrow.triangle.branch"
        case .afc: return "folder"
        case .coreMedia: return "waveform"
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
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ModuleHeader(
                        title: "Airlift Explorer",
                        subtitle: "Airlift əməliyyatlarının faktiki təqdim etdiyi fayllar üçün bölmə.",
                        symbol: "arrow.triangle.branch"
                    )
                    StatusCard(
                        title: "Airlift adapteri qoşulmayıb",
                        detail: "Bu modul ayrıca Airlift bağlantı adapteri tələb edir. Adapter qoşulmadan fayl siyahısı göstərilmir.",
                        symbol: "info.circle"
                    )
                    StatusCard(
                        title: "Giriş məhdudiyyəti",
                        detail: "Yalnız uğurla təsdiqlənmiş əməliyyat nəticələri göstəriləcək.",
                        symbol: "lock.shield"
                    )
                }
                .padding()
            }
            .navigationTitle("ProFiles")
        }
    }
}

private struct AFCExplorerView: View {
    @State private var showingImporter = false
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

                    Button {
                        showingImporter = true
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
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        try PairingFileStore.importFile(from: url)
                        pairingReady = true
                        statusMessage = "Pairing faylı ProFiles daxilində saxlanıldı."
                    } catch {
                        statusMessage = "Fayl oxunmadı: \\(error.localizedDescription)"
                        showingError = true
                    }
                case .failure(let error):
                    statusMessage = "Seçim ləğv edildi və ya uğursuz oldu: \\(error.localizedDescription)"
                    showingError = true
                }
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
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ModuleHeader(
                        title: "CoreMedia Lab",
                        subtitle: "CoreMedia testləri və diaqnostika üçün ayrıca bölmə.",
                        symbol: "waveform"
                    )
                    StatusCard(
                        title: "Test icra edilməyib",
                        detail: "Burada test nəticələri, cihaz build-i və xəta qeydləri göstəriləcək.",
                        symbol: "testtube.2"
                    )
                    StatusCard(
                        title: "Fayl meneceri deyil",
                        detail: "CoreMedia test nəticəsi öz-özlüyündə fayl sistemi icazəsi yaratmır.",
                        symbol: "exclamationmark.shield"
                    )
                }
                .padding()
            }
            .navigationTitle("CoreMedia Lab")
        }
    }
}
