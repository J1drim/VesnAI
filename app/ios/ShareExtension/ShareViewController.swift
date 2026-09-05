import UIKit
import Social

final class ShareViewController: SLComposeServiceViewController {
  private let groupID = "group.ai.vesnai.shared"
  private var saving = false

  override func isContentValid() -> Bool { !saving }

  override func didSelectPost() {
    guard !saving else { return }
    saving = true
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
      fail("The shared app group is unavailable.")
      return
    }
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    guard providers.count <= 10 else { fail("Share at most ten items."); return }
    let id = UUID().uuidString.lowercased()
    let folder = container.appendingPathComponent("shared_inbox").appendingPathComponent(id)
    do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    catch { fail(error.localizedDescription); return }
    let lock = NSLock()
    let group = DispatchGroup()
    var parts = [contentText ?? ""].filter { !$0.isEmpty }
    var files: [[String: String]] = []
    var failure: Error?
    var total = 0

    func addText(_ value: String) {
      lock.lock(); defer { lock.unlock() }
      if value.utf8.count > 1_000_000 { failure = NSError(domain: "VesnAIShare", code: 1); return }
      if !parts.contains(value) { parts.append(value) }
    }
    func copyFile(_ url: URL, _ index: Int) {
      lock.lock(); defer { lock.unlock() }
      do {
        guard !url.standardizedFileURL.path.hasPrefix(container.standardizedFileURL.path + "/") else {
          throw NSError(domain: "VesnAIShare", code: 2)
        }
        let name = String(url.lastPathComponent.prefix(240))
        let ext = url.pathExtension.lowercased()
        let safeExt = ext.range(of: "^[a-z0-9]{1,10}$", options: .regularExpression) == nil ? "bin" : ext
        let filename = "\(index).\(safeExt)"
        let target = folder.appendingPathComponent(filename)
        FileManager.default.createFile(atPath: target.path, contents: nil)
        let input = try FileHandle(forReadingFrom: url)
        let output = try FileHandle(forWritingTo: target)
        defer { try? input.close(); try? output.close() }
        while let bytes = try input.read(upToCount: 65536), !bytes.isEmpty {
          total += bytes.count
          guard total <= 50 * 1024 * 1024 else { throw NSError(domain: "VesnAIShare", code: 3) }
          try output.write(contentsOf: bytes)
        }
        try output.synchronize()
        files.append(["name": name, "path": filename])
      } catch { failure = error }
    }
    for (index, provider) in providers.enumerated() {
      group.enter()
      if provider.hasItemConformingToTypeIdentifier("public.url") && !provider.hasItemConformingToTypeIdentifier("public.file-url") {
        provider.loadItem(forTypeIdentifier: "public.url", options: nil) { value, error in
          defer { group.leave() }
          if let url = value as? URL { addText(url.absoluteString) }
          else if let value = value as? String { addText(value) }
          else { lock.lock(); failure = error ?? NSError(domain: "VesnAIShare", code: 4); lock.unlock() }
        }
      } else if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
        provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { value, error in
          defer { group.leave() }
          if let text = value as? String { addText(text) }
          else if let text = value as? NSAttributedString { addText(text.string) }
          else { lock.lock(); failure = error ?? NSError(domain: "VesnAIShare", code: 4); lock.unlock() }
        }
      } else if provider.hasItemConformingToTypeIdentifier("public.file-url") {
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { value, error in
          defer { group.leave() }
          if let url = value as? URL {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            copyFile(url, index)
          } else { lock.lock(); failure = error ?? NSError(domain: "VesnAIShare", code: 4); lock.unlock() }
        }
      } else {
        let type = provider.registeredTypeIdentifiers.first ?? "public.data"
        provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
          defer { group.leave() }
          if let url = url { copyFile(url, index) }
          else { lock.lock(); failure = error ?? NSError(domain: "VesnAIShare", code: 4); lock.unlock() }
        }
      }
    }
    group.notify(queue: .main) {
      do {
        if let error = failure { throw error }
        let text = parts.joined(separator: "\n\n")
        guard text.utf8.count <= 1_000_000, !text.isEmpty || !files.isEmpty else {
          throw NSError(domain: "VesnAIShare", code: 5)
        }
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "title": "", "text": text, "files": files])
        try data.write(to: folder.appendingPathComponent("ready.json"), options: .atomic)
        let manifest = try FileHandle(forWritingTo: folder.appendingPathComponent("ready.json"))
        try manifest.synchronize()
        try manifest.close()
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
      } catch {
        try? FileManager.default.removeItem(at: folder)
        self.fail(error.localizedDescription)
      }
    }
  }

  private func fail(_ detail: String) {
    let polish = Locale.preferredLanguages.first?.hasPrefix("pl") == true
    let alert = UIAlertController(title: "VesnAI", message: polish
      ? "Nie udało się zapisać. Limit: 10 plików, łącznie 50 MB. Spróbuj ponownie.\n\(detail)"
      : "Could not save. Limit: ten files, 50 MB total. Please retry.\n\(detail)", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
      self.extensionContext?.cancelRequest(withError: NSError(domain: "VesnAIShare", code: 1))
    })
    present(alert, animated: true)
  }
}
