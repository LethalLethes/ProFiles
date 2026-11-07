import SwiftUI
import UniformTypeIdentifiers
import AirliftFFI
import AVKit
import PDFKit
import QuickLook
import UIKit
import SQLite3
import SQLite3

private struct AFCEntry: Identifiable, Hashable, Decodable {
    let name: String
    let isDirectory: Bool
    var id: String { name }
}

private enum AFCBridgeError: LocalizedError {
    case pairingMissing
    case invalidResult(String)
    var errorDescription: String? {
        switch self {
        case .pairingMissing: return "Pairing .plist faylı tapılmadı. Əvvəlcə Pairing faylını import et."
        case .invalidResult(let message): return message
        }
    }
}

private enum AFCBridge {
    static var pairingPath: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProFiles-Pairing.plist").path
    }

    static func list(_ path: String) throws -> [AFCEntry] {
        guard FileManager.default.fileExists(atPath: pairingPath) else { throw AFCBridgeError.pairingMissing }
        var json: UnsafeMutablePointer<CChar>?
        var error: UnsafeMutablePointer<CChar>?
        let rc = pairingPath.withCString { p in
            path.withCString { r in al_afc_list_directory(p, r, &json, &error) }
        }
        defer {
            if let json { al_string_free(json) }
            if let error { al_string_free(error) }
        }
        guard rc == 0, let json else {
            throw AFCBridgeError.invalidResult(error.map { String(cString: $0) } ?? "AFC siyahılama xətası: \(rc)")
        }
        let data = Data(String(cString: json).utf8)
        return try JSONDecoder().decode([AFCEntry].self, from: data)
    }

    static func read(_ path: String) throws -> Data {
        guard FileManager.default.fileExists(atPath: pairingPath) else { throw AFCBridgeError.pairingMissing }
        var bytes: UnsafeMutablePointer<CChar>?
        var length = 0
        var error: UnsafeMutablePointer<CChar>?
        let rc = pairingPath.withCString { p in
            path.withCString { r in al_afc_read_file(p, r, &bytes, &length, &error) }
        }
        defer {
            if let bytes { al_buffer_free(bytes) }
            if let error { al_string_free(error) }
        }
        guard rc == 0, let bytes else {
            throw AFCBridgeError.invalidResult(error.map { String(cString: $0) } ?? "AFC oxuma xətası: \(rc)")
        }
        return Data(bytes: bytes, count: length)
    }
}

struct AFCFileManagerView: View {
    @State private var path = "/"
    @State private var entries: [AFCEntry] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var selectedFile: RemoteFile?
    @State private var refreshID = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("AFC qovluğu yüklənir…")
                } else if entries.isEmpty {
                    VStack(spacing: 10) { Image(systemName: "folder").font(.largeTitle); Text("Boş qovluq").font(.headline); Text("Bu AFC qovluğunda görünən element yoxdur.").foregroundStyle(.secondary) }
                } else {
                    List(entries) { entry in
                        if entry.isDirectory {
                            NavigationLink {
                                AFCFileManagerViewAtPath(path: child(entry.name))
                            } label: {
                                Label(entry.name, systemImage: "folder")
                            }
                        } else {
                            Button {
                                selectedFile = RemoteFile(path: child(entry.name), name: entry.name)
                            } label: {
                                Label(entry.name, systemImage: icon(for: entry.name))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(path == "/" ? "AFC Files" : URL(fileURLWithPath: path).lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                }
            }
            .task(id: refreshID) { load() }
            .sheet(item: $selectedFile) { file in
                AFCRemoteFilePreview(file: file)
            }
            .alert("AFC", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Bağla", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func child(_ name: String) -> String { path == "/" ? "/" + name : path + "/" + name }
    private func icon(for name: String) -> String {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "txt", "log", "md", "json", "xml", "plist", "swift", "c", "h", "py", "csv": return "doc.text"
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff", "bmp": return "photo"
        case "mov", "mp4", "m4v", "avi", "mkv", "3gp": return "film"
        case "mp3", "m4a", "wav", "aac", "flac", "caf": return "waveform"
        default: return "doc"
        }
    }
    private func load() {
        guard !loading else { return }
        loading = true
        let requestedPath = path
        Task.detached(priority: .userInitiated) {
            do {
                let names = try AFCBridge.list(requestedPath)
                await MainActor.run {
                    entries = names
                    loading = false
                }
            } catch {
                await MainActor.run {
                    entries = []
                    loading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct AFCFileManagerViewAtPath: View {
    let path: String
    @State private var entries: [AFCEntry] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var selectedFile: RemoteFile?

    var body: some View {
        Group {
            if loading { ProgressView("Yüklənir…") }
            else {
                List(entries) { entry in
                    if entry.isDirectory {
                        NavigationLink(entry.name) { AFCFileManagerViewAtPath(path: child(entry.name)) }
                    } else {
                        Button(entry.name) { selectedFile = RemoteFile(path: child(entry.name), name: entry.name) }
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .navigationTitle(URL(fileURLWithPath: path).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .sheet(item: $selectedFile) { AFCRemoteFilePreview(file: $0) }
        .alert("AFC", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Bağla", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
    private func child(_ name: String) -> String { path == "/" ? "/" + name : path + "/" + name }
    private func load() {
        loading = true
        Task.detached {
            do {
                let result = try AFCBridge.list(path)
                await MainActor.run { entries = result; loading = false }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; loading = false }
            }
        }
    }
}

private struct RemoteFile: Identifiable {
    let path: String
    let name: String
    var id: String { path }
}

private struct AFCRemoteFilePreview: View {
    let file: RemoteFile
    @Environment(\.dismiss) private var dismiss
    @State private var data: Data?
    @State private var errorMessage: String?
    @State private var loading = true
    @State private var localPreviewURL: URL?
    @State private var player: AVPlayer?

    private var ext: String { URL(fileURLWithPath: file.name).pathExtension.lowercased() }
    private var isVideo: Bool { ["mov", "mp4", "m4v", "avi", "mkv", "3gp"].contains(ext) }
    private var isSQLiteDatabase: Bool {
        guard let data else { return ["sqlite", "sqlite3", "db"].contains(ext) }
        return data.starts(with: Array("SQLite format 3\u{0}".utf8))
            || ["sqlite", "sqlite3", "db"].contains(ext)
    }
    private var textContent: String? {
        guard let data, !isSQLiteDatabase else { return nil }
        if ext == "plist",
           let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let xml = try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0) {
            return String(data: xml, encoding: .utf8)
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Fayl oxunur…")
                } else if let errorMessage {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        Text("Fayl açıla bilmədi").font(.headline)
                        Text(errorMessage).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding()
                } else if isVideo, let player {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                        .onDisappear { player.pause() }
                } else if ["png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff", "bmp"].contains(ext),
                          let data, let image = UIImage(data: data) {
                    ScrollView { Image(uiImage: image).resizable().scaledToFit().padding() }
                } else if ext == "pdf", let data {
                    PDFRemotePreview(data: data)
                } else if let textContent {
                    ScrollView {
                        Text(prettyText(textContent))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else if let localPreviewURL {
                    QuickLookRemotePreview(url: localPreviewURL)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "doc").font(.largeTitle)
                        Text("Önizləmə mümkün deyil").font(.headline)
                        Text("Faylı paylaş düyməsi ilə başqa tətbiqdə aça bilərsən.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding()
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Bağla") { dismiss() } }
                if let data {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ShareLink(item: FileTransfer(data: data, name: file.name), preview: SharePreview(file.name))
                    }
                }
            }
        }
        .task { load() }
    }

    private func load() {
        let remotePath = file.path
        let fileName = file.name
        let video = isVideo
        Task.detached(priority: .userInitiated) {
            do {
                let result = try AFCBridge.read(remotePath)
                let suffix = URL(fileURLWithPath: fileName).pathExtension
                let previewURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(suffix.isEmpty ? "bin" : suffix)
                try result.write(to: previewURL, options: .atomic)
                await MainActor.run {
                    data = result
                    localPreviewURL = previewURL
                    if video { player = AVPlayer(url: previewURL) }
                    loading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    loading = false
                }
            }
        }
    }

    private func prettyText(_ value: String) -> String {
        guard ext == "json",
              let object = try? JSONSerialization.jsonObject(with: Data(value.utf8)),
              let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: formatted, encoding: .utf8) else { return value }
        return result
    }
}

private struct QuickLookRemotePreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private struct SQLiteDatabasePreview: View {
    let url: URL
    @State private var tables: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("SQLite bazası açıla bilmədi")
                    Text(errorMessage).font(.caption).foregroundStyle(.secondary)
                }.padding()
            } else if tables.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tablecells").font(.largeTitle)
                    Text("Cədvəl tapılmadı")
                    Text("Baza boş ola bilər və ya yalnız daxili obyektlər saxlayır.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding()
            } else {
                List(tables, id: \.self) { table in
                    NavigationLink {
                        SQLiteTablePreview(url: url, table: table)
                    } label: {
                        Label(table, systemImage: "tablecells")
                    }
                }
            }
        }
        .task { loadTables() }
    }

    private func loadTables() {
        do {
            var db: OpaquePointer?
            guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
                throw SQLitePreviewError(message: "SQLite faylı açıla bilmədi.")
            }
            defer { sqlite3_close(db) }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type IN ('table','view') ORDER BY name", -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw SQLitePreviewError(message: String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            var found: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let value = sqlite3_column_text(statement, 0) {
                    found.append(String(cString: value))
                }
            }
            tables = found
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SQLiteTablePreview: View {
    let url: URL
    let table: String
    @State private var columns: [String] = []
    @State private var rows: [[String]] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            } else if columns.isEmpty {
                ProgressView("Cədvəl oxunur…")
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("İlk 100 sətir").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sətir \(index + 1)").font(.caption.bold())
                                ForEach(Array(columns.enumerated()), id: \.offset) { columnIndex, column in
                                    HStack(alignment: .top) {
                                        Text(column).font(.caption.bold()).frame(width: 120, alignment: .leading)
                                        Text(columnIndex < row.count ? row[columnIndex] : "NULL")
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }.padding()
                }
            }
        }
        .navigationTitle(table)
        .navigationBarTitleDisplayMode(.inline)
        .task { loadRows() }
    }

    private func loadRows() {
        do {
            var db: OpaquePointer?
            guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
                throw SQLitePreviewError(message: "SQLite faylı açıla bilmədi.")
            }
            defer { sqlite3_close(db) }
            let safeName = table.replacingOccurrences(of: "\"", with: "\"\"")
            let sql = "SELECT * FROM \"\(safeName)\" LIMIT 100"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw SQLitePreviewError(message: String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            let count = Int(sqlite3_column_count(statement))
            columns = (0..<count).map { index in
                String(cString: sqlite3_column_name(statement, Int32(index)))
            }
            var result: [[String]] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                var row: [String] = []
                for index in 0..<count {
                    let type = sqlite3_column_type(statement, Int32(index))
                    if type == SQLITE_NULL {
                        row.append("NULL")
                    } else if type == SQLITE_BLOB {
                        let length = Int(sqlite3_column_bytes(statement, Int32(index)))
                        if let blob = sqlite3_column_blob(statement, Int32(index)), length > 0 {
                            let bytes = Data(bytes: blob, count: min(length, 256))
                            row.append("BLOB: " + bytes.map { String(format: "%02X", $0) }.joined() + (length > 256 ? "…" : ""))
                        } else {
                            row.append("BLOB (0 bytes)")
                        }
                    } else if let value = sqlite3_column_text(statement, Int32(index)) {
                        row.append(String(cString: value))
                    } else {
                        row.append("")
                    }
                }
                result.append(row)
            }
            rows = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SQLitePreviewError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct FileTransfer: Transferable {
    let data: Data
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { $0.data }
    }
}

private struct PDFRemotePreview: View {
    let data: Data
    var body: some View {
        if let document = PDFDocument(data: data) {
            PDFKitView(document: document)
        } else {
            VStack { Image(systemName: "doc.richtext"); Text("PDF açıla bilmədi") }
        }
    }
}


private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) { view.document = document }
}
