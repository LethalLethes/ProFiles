import SwiftUI

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
    @State private var selectedTab: ProFilesTab = .airlift

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
                        title: "Airlift bağlantısı qoşulmayıb",
                        detail: "Hazırda bu ekran yalnız interfeys skeletidir. Dəstəklənən API qoşulmadan fayl və qovluq göstərilmir.",
                        symbol: "info.circle"
                    )
                    StatusCard(
                        title: "Giriş məhdudiyyəti",
                        detail: "Airlift-in sınaqdan keçmiş imkanları xaricində sistem qovluqlarına giriş vəd edilmir.",
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
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ModuleHeader(
                        title: "AFC Explorer",
                        subtitle: "Qoşulmuş cihazın paired AFC xidmətində görünən fayllar.",
                        symbol: "folder"
                    )
                    StatusCard(
                        title: "Pairing bağlantısı gözlənilir",
                        detail: "Bu başlanğıc versiyada pairing faylı oxunmur və AFC sessiyası açılmır. Real AFC adapteri ayrıca qoşulmalıdır.",
                        symbol: "cable.connector"
                    )
                    StatusCard(
                        title: "AFC namespace",
                        detail: "AFC yalnız xidmətin təqdim etdiyi sahəni göstərə bilər; bu, iOS root fayl sisteminə giriş demək deyil.",
                        symbol: "lock"
                    )
                }
                .padding()
            }
            .navigationTitle("AFC Explorer")
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
                        detail: "Burada gələcəkdə yalnız test nəticələri, cihaz build-i və xəta qeydləri göstəriləcək.",
                        symbol: "testtube.2"
                    )
                    StatusCard(
                        title: "Fayl meneceri deyil",
                        detail: "CoreMedia PoC nəticəsi öz-özlüyündə fayl sistemi icazəsi və ya faylları oxuma imkanı yaratmır.",
                        symbol: "exclamationmark.shield"
                    )
                }
                .padding()
            }
            .navigationTitle("CoreMedia Lab")
        }
    }
}
