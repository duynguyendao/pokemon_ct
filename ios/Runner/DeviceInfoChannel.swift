import UIKit
import WebKit

class DeviceInfoChannel {
  static let shared = DeviceInfoChannel()
  private init() {}

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.pokemonct/device_info",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getDeviceInfo":
        result(self?.deviceInfo())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func deviceInfo() -> [String: Any] {
    let screen = UIScreen.main
    let scale = screen.scale
    let bounds = screen.bounds
    let w = Int(bounds.width * scale)
    let h = Int(bounds.height * scale)
    return [
      "screenWidth": w,
      "screenHeight": h,
      "devicePixelRatio": Double(scale),
      "deviceMemory": tieredMemory(),
      "hardwareConcurrency": ProcessInfo.processInfo.activeProcessorCount,
      "platform": "iPhone",
      "vendor": "Apple Computer, Inc.",
    ]
  }

  private func tieredMemory() -> Int {
    let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    if gb < 1 { return 1 }
    if gb < 2 { return 2 }
    if gb < 5 { return 4 }
    return 8
  }

  func installContentRules() {
    let rules = """
    [
      {"trigger":{"url-filter":"/_bm/"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"/akam/"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"bm_sz"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"/sensor_data"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"akamaiedge\\\\.net/sensor"},"action":{"type":"block"}}
    ]
    """
    WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: "akamai_block",
      encodedContentRuleList: rules
    ) { ruleList, _ in
      guard let ruleList = ruleList else { return }
      WKWebViewRulePatcher.shared.ruleList = ruleList
      WKWebViewRulePatcher.shared.install()
    }
  }
}

class WKWebViewRulePatcher: NSObject {
  static let shared = WKWebViewRulePatcher()
  var ruleList: WKContentRuleList?
  private var swizzled = false

  func install() {
    guard !swizzled else { return }
    swizzled = true
    let orig = #selector(WKWebView.init(frame:configuration:))
    let repl = #selector(WKWebView.pk_init(frame:configuration:))
    guard
      let origMethod = class_getInstanceMethod(WKWebView.self, orig),
      let replMethod = class_getInstanceMethod(WKWebView.self, repl)
    else { return }
    method_exchangeImplementations(origMethod, replMethod)
  }
}

extension WKWebView {
  @objc func pk_init(frame: CGRect, configuration: WKWebViewConfiguration) -> WKWebView {
    if let list = WKWebViewRulePatcher.shared.ruleList {
      configuration.userContentController.add(list)
    }
    // After method_exchangeImplementations, calling pk_init here invokes the original init.
    return pk_init(frame: frame, configuration: configuration)
  }
}
