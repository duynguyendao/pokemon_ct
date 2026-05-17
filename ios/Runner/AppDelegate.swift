import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WebRTCBlocker.shared.install()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Lấy FlutterViewController sau khi engine khởi xong để đăng ký MethodChannel
    DispatchQueue.main.async {
      guard
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
        let controller = scene.windows.first?.rootViewController as? FlutterViewController
      else { return }

      // Device info + content-rule channel
      DeviceInfoChannel.shared.register(messenger: controller.binaryMessenger)
      DeviceInfoChannel.shared.installContentRules()

      FlutterMethodChannel(name: "com.pokemonct/utils",
                           binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { (call, result) in
          switch call.method {

          // Trả về changeCount — KHÔNG đọc nội dung clipboard → không trigger paste dialog
          case "clipboardChangeCount":
            result(UIPasteboard.general.changeCount)

          // Mở app Mail gốc iOS (sẽ mở compose view vì iOS không hỗ trợ mở inbox trực tiếp)
          case "openMailApp":
            if let url = URL(string: "mailto:") {
              UIApplication.shared.open(url, options: [:]) { _ in }
            }
            result(nil)

          default:
            result(FlutterMethodNotImplemented)
          }
        }
    }
  }
}
