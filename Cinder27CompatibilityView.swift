import SwiftUI
import Foundation

private struct CinderTest: Identifiable {
    let id: String
    let title: String
    let area: String
    let risk: String
    let safeToProbe: Bool
}

struct Cinder27CompatibilityView: View {
    @State private var query = ""
    @State private var selected: CinderTest?
    @State private var showingConfirmation = false
    @State private var showingInfo = false
    @State private var lastResult = "Heç bir test aparılmayıb."
    @State private var resultPassed = false

    private let tests: [CinderTest] = [
        .init(id:"vid.hevc",title:"HEVC video qatlarının yoxlanması",area:"VideoToolbox",risk:"Tətbiq / sistem prosesi riski",safeToProbe:false),
        .init(id:"vid.avc",title:"AVC video dilimlərinin yoxlanması",area:"VideoToolbox",risk:"Tətbiq / sistem prosesi riski",safeToProbe:false),
        .init(id:"mdl.usda",title:"USDA model faylının yoxlanması",area:"Model I/O",risk:"Tətbiqin çökməsi mümkündür",safeToProbe:false),
        .init(id:"iio.tiff.direntry",title:"TIFF kataloq qeydlərinin yoxlanması",area:"ImageIO",risk:"Yaddaş xətası riski",safeToProbe:false),
        .init(id:"kern.ipc",title:"Kernel IPC əlaqələrinin yoxlanması",area:"XNU kernel",risk:"Cihazın yenidən başlaması mümkündür",safeToProbe:false),
        .init(id:"probe.hid",title:"HID qurğularının yoxlanması",area:"IOHID",risk:"Xidmət / sistem prosesi riski",safeToProbe:false),
        .init(id:"arc.iso",title:"ISO arxivinin yoxlanması",area:"Arxiv",risk:"Tətbiqin donması və ya çökməsi mümkündür",safeToProbe:false),
        .init(id:"arc.iso.stress",title:"ISO arxivinin yüklənmə sınağı",area:"Arxiv",risk:"Tətbiqin donması və ya çökməsi mümkündür",safeToProbe:false),
        .init(id:"arc.cab",title:"CAB arxivinin yoxlanması",area:"Arxiv",risk:"Tətbiqin çökməsi mümkündür",safeToProbe:false),
        .init(id:"aud.hoa",title:"Məkan səsinin yoxlanması",area:"AudioToolbox",risk:"Sistem prosesi riski",safeToProbe:false),
        .init(id:"kext.gpt",title:"GPT bölmə cədvəlinin yoxlanması",area:"Kernel / yaddaş",risk:"Kernel səviyyəli risk",safeToProbe:false),
        .init(id:"iio.jpeg.comment",title:"JPEG EXIF şərh məlumatının yoxlanması",area:"ImageIO",risk:"Məlumat oxunması riski",safeToProbe:false),
        .init(id:"cg.cmap",title:"PDF CMap xəritəsinin yoxlanması",area:"CoreGraphics",risk:"Tətbiqin çökməsi mümkündür",safeToProbe:false),
        .init(id:"cg.shading",title:"PDF kölgələndirmə xətasının yoxlanması",area:"CoreGraphics",risk:"Tətbiq çökə bilər",safeToProbe:false),
        .init(id:"cg.shading.sweep",title:"PDF kölgələndirmə həddinin sınağı",area:"CoreGraphics",risk:"Tətbiq çökə bilər",safeToProbe:false),
        .init(id:"cal.unzip",title:"Təqvim əlavələrinin arxivdən çıxarılması",area:"Calendar",risk:"Sistem prosesi riski",safeToProbe:false),
        .init(id:"lp.heic",title:"HEIC animasiyalı önbaxışın yoxlanması",area:"LinkPresentation",risk:"Tətbiq / sistem prosesi riski",safeToProbe:false),
        .init(id:"lp.heic.fire",title:"HEIC önbaxışının əlavə sınağı",area:"LinkPresentation",risk:"Tətbiq / sistem prosesi riski",safeToProbe:false),
        .init(id:"iio.ktx2",title:"KTX2 ölçü hesablamalarının yoxlanması",area:"ImageIO",risk:"Tətbiqin çökməsi mümkündür",safeToProbe:false),
        .init(id:"iio.pvr",title:"PVR tekstura faylının yoxlanması",area:"ImageIO",risk:"Tətbiqin çökməsi mümkündür",safeToProbe:false),
        .init(id:"iio.dds.bc7",title:"DDS / BC7 teksturasının yoxlanması",area:"ImageIO",risk:"Tətbiqin çökməsi mümkündür",safeToProbe:false),
        .init(id:"iio.appx",title:"JPEG APP məlumatının yoxlanması",area:"ImageIO",risk:"Məlumat oxunması riski",safeToProbe:false),
        .init(id:"iio.jpeg.gps",title:"JPEG GPS məlumatının yoxlanması",area:"ImageIO",risk:"Məlumat oxunması riski",safeToProbe:false),
        .init(id:"iio.apng.fctl",title:"APNG animasiya başlığının yoxlanması",area:"ImageIO",risk:"Tətbiqin çökməsi mümkündür",safeToProbe:false),
        .init(id:"iio.tiff.trunc",title:"Kəsilmiş TIFF məlumatının yoxlanması",area:"ImageIO",risk:"Məlumat oxunması riski",safeToProbe:false),
        .init(id:"iio.tiff.planar",title:"TIFF planar məlumatının yoxlanması",area:"ImageIO",risk:"Tətbiqin çökməsi mümkündür",safeToProbe:false),
        .init(id:"iio.pdf.raster",title:"PDF təsvirə çevirmə buferinin yoxlanması",area:"ImageIO",risk:"Tətbiqin çökməsi mümkündür",safeToProbe:false),
        .init(id:"iio.jpeg.marker",title:"JPEG marker uzunluğunun yoxlanması",area:"ImageIO",risk:"Məlumat oxunması riski",safeToProbe:false),
        .init(id:"aud.lc3",title:"LC3 audio dekoderinin yoxlanması",area:"AudioToolbox",risk:"Sistem prosesi riski",safeToProbe:false),
        .init(id:"sb.stash",title:"SpringBoard düzülüş məlumatının yoxlanması",area:"SpringBoard",risk:"Cihazın yenidən başlaması mümkündür",safeToProbe:false),
        .init(id:"font.gdef",title:"Şrift GDEF məlumatının yoxlanması",area:"CoreText",risk:"Tətbiqin çökməsi mümkündür",safeToProbe:false),
        .init(id:"font.cff",title:"CFF şrift məlumatının yoxlanması",area:"FontParser",risk:"Tətbiqin çökməsi mümkündür",safeToProbe:false),
        .init(id:"cm.rpu",title:"Dolby Vision RPU məlumatının yoxlanması",area:"CoreMedia",risk:"Sistem prosesi riski",safeToProbe:false),
        .init(id:"cm.rpu.sweep",title:"Dolby Vision RPU hədd sınağı",area:"CoreMedia",risk:"Sistem prosesi riski",safeToProbe:false),
        .init(id:"probe.ane",title:"Apple Neural Engine əlçatanlığının yoxlanması",area:"Neural Engine",risk:"Kernel səviyyəli risk",safeToProbe:false),
        .init(id:"ave.ntl",title:"HEVC kodlayıcı qat sayının yoxlanması",area:"VideoToolbox",risk:"Cihazın yenidən başlaması mümkündür",safeToProbe:false),
        .init(id:"ave.ntl.fire",title:"HEVC kodlayıcı sərhəd sınağı",area:"VideoToolbox",risk:"Cihazın yenidən başlaması mümkündür",safeToProbe:false),
        .init(id:"cm.fdleak",title:"CoreMedia fayl deskriptorunun yoxlanması",area:"CoreMedia",risk:"Qorunan fayllara çıxış cəhdi",safeToProbe:false),
        .init(id:"cm.fdleak.boundary",title:"CoreMedia giriş sərhədlərinin yoxlanması",area:"CoreMedia",risk:"Qorunan yolların yoxlanması",safeToProbe:false),
        .init(id:"aud.haptic",title:"Haptik audio məlumatının yoxlanması",area:"AudioToolbox",risk:"Sistem prosesi riski",safeToProbe:false),
        .init(id:"aud.immersive",title:"İmmersiv audio girişinin yoxlanması",area:"AudioToolbox",risk:"Sistem prosesi riski",safeToProbe:false),
        .init(id:"kern.decmpfs",title:"Kernel sıxılma məlumatının yoxlanması",area:"XNU kernel",risk:"Kernel səviyyəli risk",safeToProbe:false),
        .init(id:"aud.drc",title:"MPEG-D səs dinamik diapazonunun yoxlanması",area:"AudioToolbox",risk:"Sistem prosesi riski",safeToProbe:false),
        .init(id:"kext.iohid",title:"IOHID kernel hadisələrinin yoxlanması",area:"IOKit",risk:"Cihazın yenidən başlaması mümkündür",safeToProbe:false),
        .init(id:"sc.dynamicstore",title:"Şəbəkə məlumatı əlçatanlığının yoxlanması",area:"SystemConfiguration",risk:"Məlumat məxfiliyi riski",safeToProbe:false),
        .init(id:"kern.ipc.lifecycle",title:"Kernel IPC həyat dövrünün yoxlanması",area:"XNU kernel",risk:"Kernel səviyyəli risk",safeToProbe:false),
        .init(id:"kern.baseline",title:"Kernel əlaqələrinin ilkin vəziyyəti",area:"Təhlükəsiz yoxlama",risk:"Aşağı risk — yalnız müşahidə",safeToProbe:true),
        .init(id:"probe.privset",title:"Tətbiqin icazələrinin yoxlanması",area:"Təhlükəsiz yoxlama",risk:"Aşağı risk — yalnız müşahidə",safeToProbe:true),
        .init(id:"arc.rr",title:"RockRidge arxiv dövrəsinin yoxlanması",area:"Arxiv",risk:"Tətbiq dona bilər",safeToProbe:false),
        .init(id:"sbx.toctou",title:"Sandbox keçid sərhədinin yoxlanması",area:"Təhlükəsizlik",risk:"Qorunan fayllara çıxış cəhdi",safeToProbe:false),
        .init(id:"tool.ipa",title:"IPA faylının daxili yoxlanması",area:"Alət",risk:"Aşağı risk — lokal sınaq",safeToProbe:true),
        .init(id:"tool.zip",title:"ZIP arxivinin yazma/oxuma sınağı",area:"Alət",risk:"Aşağı risk — lokal sınaq",safeToProbe:true),
        .init(id:"tool.macho",title:"Mach-O icra faylının yoxlanması",area:"Alət",risk:"Aşağı risk — yalnız oxu",safeToProbe:true),
        .init(id:"tool.hex",title:"HEX axtarış və əvəzləmə sınağı",area:"Alət",risk:"Aşağı risk — lokal sınaq",safeToProbe:true),
        .init(id:"tool.container",title:"Tətbiq qovluğunun oxu/yazma sınağı",area:"Alət",risk:"Aşağı risk — öz qovluğu daxilində",safeToProbe:true),
        .init(id:"tool.backup",title:"Ehtiyat nüsxə və bərpa sınağı",area:"Alət",risk:"Aşağı risk — lokal sınaq",safeToProbe:true),
        .init(id:"tool.paths",title:"Fayl yollarının icazə yoxlaması",area:"Alət",risk:"Aşağı risk — yalnız öz qovluğu",safeToProbe:true)
    ]

    private var filtered: [CinderTest] {
        guard !query.isEmpty else { return tests }
        return tests.filter { $0.id.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query) || $0.area.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cinder27 uyğunluq yoxlaması").font(.title2.bold())
                        Text("iPhone SE (2020) • iOS 27.0.1")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Mənbə kataloqunda 57 modul göstərilir. Bu siyahı testləri tanıdır; təhlükəli PoC kodları hələ ProFiles-ə qoşulmayıb.")
                            .font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            Label("\(tests.count) qeyd", systemImage: "list.bullet")
                            Spacer()
                            Label("0 nəticə", systemImage: "checkmark.circle")
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
                Section("Nəticə") {
                    Label(lastResult, systemImage: resultPassed ? "checkmark.circle.fill" : "info.circle")
                        .font(.subheadline)
                }
                Section("Testlər") {
                    ForEach(filtered) { test in
                        Button {
                            selected = test
                            showingInfo = true
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(test.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Spacer()
                                    Text(test.safeToProbe ? "Aşağı risk" : "Riskli")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(test.safeToProbe ? .green : .orange)
                                }
                                HStack {
                                    Text(test.id).font(.caption.monospaced())
                                    Text("•")
                                    Text(test.area).font(.caption)
                                }.foregroundStyle(.secondary)
                                Text(test.risk).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $query, prompt: "Test və ya modul axtar")
            .navigationTitle("Cinder27")
            .navigationBarTitleDisplayMode(.inline)
            .alert(selected?.title ?? "Test məlumatı", isPresented: $showingInfo) {
                if selected?.safeToProbe == true {
                    Button("Davam et") { showingConfirmation = true }
                }
                Button("Bağla", role: .cancel) { }
            } message: {
                Text((selected?.risk ?? "") + "\n\n" + ((selected?.safeToProbe == true) ? "Bu mərhələdə yalnız ProFiles-in öz qovluğunda zərərsiz sınaq aparıla bilər. Bu, Cinder27 PoC nəticəsi sayılmır." : "Bu PoC yaddaş xətası, tətbiq çöküşü və ya cihazın yenidən başlamasına səbəb ola bilər. Bu build-də həmin PoC işə salınmır."))
            }
            .confirmationDialog("Təhlükəsiz lokal sınaq", isPresented: $showingConfirmation, titleVisibility: .visible) {
                Button("Həə, sınağı başlat") { runLocalSelfTest() }
                Button("Xeyr, ləğv et", role: .cancel) { }
            } message: {
                Text("Yalnız ProFiles-in öz Documents qovluğunda müvəqqəti fayl yaradılacaq, oxunacaq və silinəcək.")
            }
        }
    }

    private func runLocalSelfTest() {
        guard let selected else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProFiles-Cinder27-SafeTest.tmp")
        do {
            let marker = "ProFiles local compatibility check"
            try Data(marker.utf8).write(to: url, options: .atomic)
            let readBack = try String(contentsOf: url, encoding: .utf8)
            guard readBack == marker else { throw NSError(domain: "ProFiles.Cinder27", code: 1) }
            try FileManager.default.removeItem(at: url)
            resultPassed = true
            lastResult = "\(selected.id): lokal yazma/oxuma/silmə uğurludur. Bu Cinder27 zəiflik testi deyil."
        } catch {
            resultPassed = false
            lastResult = "\(selected.id): lokal sınaq xətası — \(error.localizedDescription)"
        }
    }
}
