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
  }
}
