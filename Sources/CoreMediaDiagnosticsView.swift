import SwiftUI
import UniformTypeIdentifiers

/// Safe CoreMedia diagnostics UI. This does not invoke the vulnerable XPC path
/// or attempt to escape the app sandbox.
struct CoreMediaDiagnosticsView: View {
    @State private var selfTestStatus = "Hələ yoxlanmayıb"
    @State private var selfTestPassed = false
    @State private var showingLogPicker = false
    @State private var logName = "Log seçilməyib"
    @State private var logSummary = "CoreMedia / panic log faylını import edib xülasəsinə bax."
    @State private var logLoaded = false

    private var testFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProFiles-CoreMedia-SelfTest.txt")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.cyan)
                        Text("CoreMedia Explorer")
                            .font(.largeTitle.bold())
                        Text("Ayrı modul • AFC və Airlift-dən müstəqil")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    statusCard(
                        title: "CoreMedia PoC statusu",
                        detail: "Bu build CoreMedia XPC exploitini işə salmır. Ona görə hələlik CoreMedia FD və real cihaz qovluqları göstərilmir. Bu status qəsdən belə göstərilir ki, lokal sandbox testi CoreMedia girişilə səhv salınmasın.",
                        symbol: "info.circle"
                    )

                    statusCard(
                        title: selfTestPassed ? "Lokal fayl testi uğurlu" : "Lokal fayl testi",
                        detail: selfTestStatus,
                        symbol: selfTestPassed ? "checkmark.circle.fill" : "doc.text.magnifyingglass"
                    )

                    Button(action: runLocalSelfTest) {
                        Label("Lokal fayl testini işə sal", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    statusCard(
                        title: logLoaded ? "Log yükləndi: \(logName)" : "Crash / panic log",
                        detail: logSummary,
                        symbol: "doc.text"
                    )

                    Button {
                        showingLogPicker = true
                    } label: {
                        Label("Crash / panic log import et", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    statusCard(
                        title: "PoC-nin sənədləşdirilmiş sərhədi",
                        detail: "CoreMedia FD leak PoC üçün göstərilən əsas sahə Media/iTunes_Control/iTunes qovluğudur. Başqa tətbiqlərin sandbox-ları bu PoC ilə açılmır. Bu ekran hələ həmin FD mexanizmini qoşmur.",
                        symbol: "lock.shield"
                    )

                    statusCard(
                        title: "Növbəti real inteqrasiya mərhələsi",
                        detail: "CoreMedia adapteri ayrıca provider kimi qoşulmalı, hər açılan FD üçün yol, fstat nəticəsi və oxu xətası ayrıca göstərilməlidir. Bu build-də belə nəticə uydurulmur.",
                        symbol: "point.3.connected.trianglepath.dotted"
                    )
                }
                .padding()
            }
            .navigationTitle("CoreMedia")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showingLogPicker,
                allowedContentTypes: [.data, .plainText, .json],
                allowsMultipleSelection: false
            ) { result in
                importLog(result)
            }
        }
    }

    private func statusCard(title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func runLocalSelfTest() {
        let marker = "ProFiles CoreMedia module self-test"
        do {
            try marker.data(using: .utf8)!.write(to: testFileURL, options: .atomic)
            let readBack = try String(contentsOf: testFileURL, encoding: .utf8)
            guard readBack == marker else {
                throw NSError(
                    domain: "ProFiles.CoreMediaDiagnostics",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Yazılan və oxunan məzmun uyğun gəlmədi."]
                )
            }
            try FileManager.default.removeItem(at: testFileURL)
            selfTestPassed = true
            selfTestStatus = "Documents daxilində test faylı yaradıldı, oxundu, məzmun təsdiqləndi və silindi. Bu yalnız tətbiqin öz sandbox-ını yoxlayır; CoreMedia exploit testi deyil."
        } catch {
            selfTestPassed = false
            selfTestStatus = "Lokal test xətası: \(error.localizedDescription)"
        }
    }

    private func importLog(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let content = String(data: data, encoding: .utf8) ?? "Fayl UTF-8 mətn deyil."
            let lines = content.components(separatedBy: .newlines)
            let preview = lines.prefix(12).joined(separator: "\n")
            logName = url.lastPathComponent
            logSummary = "Ölçü: \(data.count) bayt\n\(preview.prefix(1200))"
            logLoaded = true
        } catch {
            logLoaded = false
            logSummary = "Log oxunmadı: \(error.localizedDescription)"
        }
    }
}
