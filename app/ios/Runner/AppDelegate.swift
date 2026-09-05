import Flutter
import UIKit
import WidgetKit
import AVFoundation
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let appGroupId = "group.ai.vesnai.shared"
  private let snapshotKey = "widget_snapshot"
  private let capturesKey = "quick_captures"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Background poll of the VesnAI notification feed (BGTaskScheduler).
    // The identifier must match Info.plist and kBackgroundPollTask in Dart.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "ai.vesnai.notificationPoll",
      frequency: NSNumber(value: 15 * 60))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VesnaiWidgets") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "vesnai/widgets", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, let defaults = UserDefaults(suiteName: self.appGroupId) else {
        result(nil)
        return
      }
      switch call.method {
      case "writeSnapshot":
        defaults.set(call.arguments as? String, forKey: self.snapshotKey)
        if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() }
        result(nil)
      case "readSnapshot":
        result(defaults.string(forKey: self.snapshotKey))
      case "drainQuickCaptures":
        let raw = defaults.string(forKey: self.capturesKey)
        defaults.removeObject(forKey: self.capturesKey)
        result(raw)
      case "pushQuickCapture":
        guard let arg = call.arguments as? String,
          let data = arg.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data)
        else {
          result(nil)
          return
        }
        var items: [Any] = []
        if let existing = defaults.string(forKey: self.capturesKey),
          let existingData = existing.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: existingData) as? [Any]
        {
          items = arr
        }
        items.append(obj)
        if let out = try? JSONSerialization.data(withJSONObject: items),
          let str = String(data: out, encoding: .utf8)
        {
          defaults.set(str, forKey: self.capturesKey)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let volumeChannel = FlutterMethodChannel(
      name: "vesnai/media_volume", binaryMessenger: registrar.messenger())
    volumeChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getMusicVolume":
        result(Double(AVAudioSession.sharedInstance().outputVolume))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let sharesChannel = FlutterMethodChannel(name: "vesnai/shares", binaryMessenger: registrar.messenger())
    let shareQueue = DispatchQueue(label: "ai.vesnai.shared-inbox")
    sharesChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self,
        let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: self.appGroupId)
      else { result(FlutterError(code: "share_group", message: "Shared app group unavailable", details: nil)); return }
      shareQueue.async {
        do {
          let root = group.appendingPathComponent("shared_inbox")
          try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
          if call.method == "list" {
            var items: [[String: Any]] = []
            for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
              let manifest = folder.appendingPathComponent("ready.json")
              guard FileManager.default.fileExists(atPath: manifest.path) else { continue }
              guard var item = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any] else {
                throw NSError(domain: "VesnAIShare", code: 2)
              }
              var files: [[String: String]] = []
              for file in item["files"] as? [[String: String]] ?? [] {
                var value = file
                guard let path = file["path"] else { throw NSError(domain: "VesnAIShare", code: 2) }
                value["path"] = folder.appendingPathComponent((path as NSString).lastPathComponent).path
                files.append(value)
              }
              item["files"] = files
              items.append(item)
            }
            let data = try JSONSerialization.data(withJSONObject: items)
            DispatchQueue.main.async { result(String(data: data, encoding: .utf8)) }
          } else if call.method == "ack" {
            guard let id = call.arguments as? String,
              id.range(of: "^[a-fA-F0-9-]{36}$", options: .regularExpression) != nil
            else { throw NSError(domain: "VesnAIShare", code: 1) }
            let folder = root.appendingPathComponent(id)
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            DispatchQueue.main.async { result(nil) }
          } else { DispatchQueue.main.async { result(FlutterMethodNotImplemented) } }
        } catch { DispatchQueue.main.async { result(FlutterError(code: "share_failed", message: error.localizedDescription, details: nil)) } }
      }
    }
  }
}
