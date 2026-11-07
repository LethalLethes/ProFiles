import SwiftUI
import UniformTypeIdentifiers
import AirliftFFI

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
        case "png", "jpg", "jpeg", "heic", "gif": return "photo"
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

    private var ext: String { URL(fileURLWithPath: file.name).pathExtension.lowercased() }
    private var textContent: String? { data.flatMap { String(data: $0, encoding: .utf8) } }

    var body: some View {
        NavigationStack {
            Group {
                if loading { ProgressView("Fayl oxunur…") }
                else if let errorMessage { VStack(spacing: 10) { Image(systemName: "exclamationmark.triangle").font(.largeTitle); Text("Fayl açıla bilmədi").font(.headline); Text(errorMessage).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding() }
                else if ["png","jpg","jpeg","heic","gif"].contains(ext), let data, let image = UIImage(data: data) {
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
                } else {
                    VStack(spacing: 10) { Image(systemName: "doc").font(.largeTitle); Text("Önizləmə mümkün deyil").font(.headline); Text("Bu format UTF-8 mətn, PDF və ya dəstəklənən şəkil deyil.").foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding()
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
        Task.detached(priority: .userInitiated) {
            do {
                let result = try AFCBridge.read(file.path)
                await MainActor.run { data = result; loading = false }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; loading = false }
            }
        }
    }

    private func prettyText(_ value: String) -> String {
        guard ext == "json", let object = try? JSONSerialization.jsonObject(with: Data(value.utf8)),
              let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: formatted, encoding: .utf8) else { return value }
        return result
    }
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

import PDFKit
import UIKit

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
