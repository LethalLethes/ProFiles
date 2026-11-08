import SwiftUI
import UniformTypeIdentifiers
import CoreFoundation

/// Edits a user-selected MobileGestalt/property-list export as a separate copy.
/// It does not access or modify the live protected system database.
struct MobileGestaltEditorView: View {
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var values: [String: Any] = [:]
    @State private var selectedKey: String? = nil
    @State private var draftValue = ""
    @State private var isBoolean = false
    @State private var booleanValue = false
    @State private var editable = false
    @State private var status = "MobileGestalt plist faylını import et. Orijinal fayl dəyişdirilmir."
    @State private var exportDocument = PlistExportDocument(data: Data())

    private var keys: [String] { values.keys.sorted() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("MobileGestalt Editor", systemImage: "slider.horizontal.3")
                        .font(.title2.bold())
                    Text("İstifadəçinin seçdiyi plist surətini oxuyur və redaktə edir. Canlı sistem bazasına və qorunan fayllara birbaşa yazmır.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Fayl") {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Plist import et", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)

                    Text(status)
                        .font(.footnote)
                        .textSelection(.enabled)

                    if !values.isEmpty {
                        Text("\(values.count) əsas açar tapıldı")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !values.isEmpty {
                    Section("Açar seç") {
                        Picker("MobileGestalt açarı", selection: $selectedKey) {
                            Text("Seçilməyib").tag(String?.none)
                            ForEach(keys, id: \.self) { key in
                                Text(key).tag(Optional(key))
                            }
                        }
                        .onChange(of: selectedKey) { newValue in
                            loadDraft(for: newValue)
                        }
                    }
                }

                if let key = selectedKey, let value = values[key] {
                    Section("Dəyər") {
                        Text("Tip: \(typeName(value))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if editable && isBoolean {
                            Toggle("Dəyər", isOn: $booleanValue)
                        } else if editable {
                            TextField("Yeni dəyər", text: $draftValue, axis: .vertical)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            Text(displayValue(value))
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        if editable {
                            Button("Dəyişikliyi tətbiq et") {
                                applyDraft(for: key)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                if !values.isEmpty {
                    Section("Export") {
                        Button {
                            do {
                                let data = try PropertyListSerialization.data(
                                    fromPropertyList: values,
                                    format: .xml,
                                    options: 0
                                )
                                exportDocument = PlistExportDocument(data: data)
                                showingExporter = true
                            } catch {
                                status = "Export xətası: \(error.localizedDescription)"
                            }
                        } label: {
                            Label("Redaktə edilmiş plist-i export et", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section("Qeyd") {
                    Text("Bu modul yalnız import etdiyin faylın surətini dəyişir. iOS-un canlı MobileGestalt bazasına yazma, sistem qorumasını keçmə və cihaz funksiyalarını birbaşa aktivləşdirmə etmir.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("MobileGestalt")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.propertyList, .data],
                allowsMultipleSelection: false
            ) { result in
                importPlist(result)
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .propertyList,
                defaultFilename: "MobileGestalt-Edited"
            ) { result in
                switch result {
                case .success(let url):
                    status = "Export edildi: \(url.lastPathComponent)"
                case .failure(let error):
                    status = "Export alınmadı: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importPlist(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dictionary = object as? [String: Any] else {
                throw NSError(domain: "ProFiles.MobileGestalt", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Plist-in əsas elementi dictionary deyil."])
            }
            values = dictionary
            selectedKey = keys.first
            loadDraft(for: selectedKey)
            status = "\(url.lastPathComponent) import edildi. Orijinal fayl toxunulmaz qaldı."
        } catch {
            status = "Import xətası: \(error.localizedDescription)"
        }
    }

    private func loadDraft(for key: String?) {
        guard let key, let value = values[key] else {
            editable = false
            isBoolean = false
            draftValue = ""
            return
        }
        if let string = value as? String {
            draftValue = string
            editable = true
            isBoolean = false
        } else if let number = value as? NSNumber {
            editable = true
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                isBoolean = true
                booleanValue = number.boolValue
                draftValue = ""
            } else {
                isBoolean = false
                draftValue = number.stringValue
            }
        } else {
            editable = false
            isBoolean = false
            draftValue = ""
        }
    }

    private func applyDraft(for key: String) {
        guard let old = values[key] else { return }
        if let number = old as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                values[key] = NSNumber(value: booleanValue)
            } else if String(cString: number.objCType) == "f" || String(cString: number.objCType) == "d" {
                guard let parsed = Double(draftValue) else {
                    status = "Yanlış rəqəm formatı."
                    return
                }
                values[key] = NSNumber(value: parsed)
            } else {
                guard let parsed = Int64(draftValue) else {
                    status = "Tam ədəd formatı düzgün deyil."
                    return
                }
                values[key] = NSNumber(value: parsed)
            }
        } else {
            values[key] = draftValue
        }
        status = "\(key) dəyəri redaktə edildi. Dəyişiklik export edilən surətə aiddir."
        loadDraft(for: key)
    }

    private func typeName(_ value: Any) -> String {
        if value is String { return "String" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "Boolean" : "Number"
        }
        if value is [String: Any] { return "Dictionary (yalnız oxu)" }
        if value is [Any] { return "Array (yalnız oxu)" }
        if value is Data { return "Data (yalnız oxu)" }
        return "Digər (yalnız oxu)"
    }

    private func displayValue(_ value: Any) -> String {
        if let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0),
           let text = String(data: data, encoding: .utf8) {
            return String(text.prefix(4000))
        }
        return String(describing: value)
    }
}

private struct PlistExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.propertyList] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
