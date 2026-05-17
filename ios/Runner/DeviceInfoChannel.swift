import UIKit
import Flutter
import WebKit

/// Cung cấp giá trị device thực ở native level để fingerprint script
/// dùng giá trị khớp với hardware thật — không thể bị detect là JS-faked.
///
/// Ngoài ra cài WKContentRuleList để block Akamai sensor/telemetry endpoint
/// ở tầng network (trước khi JS của page chạy).
class DeviceInfoChannel {
  static let shared = DeviceInfoChannel()

  private init() {}

  // MARK: - MethodChannel registration

  func register(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "com.pokemonct/device_info",
                         binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self else { return }
        switch call.method {
        case "getDeviceInfo":
          result(self.deviceInfo())
        case "installContentRules":
          let identifier = (call.arguments as? String) ?? "default"
          self.installContentRules(identifier: identifier)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }

  // MARK: - Device info (native values, slightly tiered for privacy)

  private func deviceInfo() -> [String: Any] {
    let screen = UIScreen.main
    let bounds = screen.bounds
    let scale  = screen.scale

    // CSS pixel dimensions (logical, not physical)
    let cssW = Int(bounds.width)
    let cssH = Int(bounds.height)

    // Memory tier: bucket real RAM to avoid exact fingerprinting
    let memoryGB = tieredMemory()

    // CPU count: real value (WebKit exposes hardwareConcurrency natively anyway)
    let cpuCount = ProcessInfo.processInfo.activeProcessorCount

    return [
      "screenWidth":       cssW,
      "screenHeight":      cssH,
      "devicePixelRatio":  Double(scale),
      "deviceMemory":      memoryGB,
      "hardwareConcurrency": cpuCount,
      "platform":          "iPhone",
      "vendor":            "Apple Computer, Inc.",
    ]
  }

  /// Bucket physical RAM into the tiers browsers report (0.25/0.5/1/2/4/8 GB).
  private func tieredMemory() -> Int {
    let bytes = ProcessInfo.processInfo.physicalMemory
    let gb    = Double(bytes) / 1_073_741_824
    switch gb {
    case ..<1:   return 1
    case ..<2:   return 2
    case ..<5:   return 4
    default:     return 8
    }
  }

  // MARK: - WKContentRuleList (block Akamai sensor endpoints natively)

  func installContentRules(identifier: String = "akamai_block") {
    // Block known Akamai Bot Manager sensor/telemetry paths.
    // These requests are made by Akamai's _ak_bmsc / bm_sz scripts to collect
    // device fingerprint data. Blocking them at network layer means the JS
    // never gets a response, degrading Akamai's detection confidence.
    let rules = """
    [
      {
        "trigger": {
          "url-filter": "/_bm/|/akam/|/akam-sw\\\\.js|/ak_bmsc|bm_sz|/sensor_data"
        },
        "action": { "type": "block" }
      },
      {
        "trigger": {
          "url-filter": "akamaiedge\\\\.net/sensor|akamai\\\\.net/sensor"
        },
        "action": { "type": "block" }
      }
    ]
    """
    WKContentRuleListStore.default()?.compileContentRuleList(
      forIdentifier: identifier,
      encodedContentRuleList: rules
    ) { ruleList, error in
      guard let ruleList, error == nil else { return }
      // Swizzle WKWebView init to inject the rule list into all future instances.
      WKWebViewRulePatcher.shared.ruleList = ruleList
    }
  }
}

// MARK: - WKWebView swizzle to inject content rules into every instance

/// Patches every WKWebView created in this process (including webview_flutter's)
/// to include our content blocking rules — without touching the Flutter plugin.
class WKWebViewRulePatcher: NSObject {
  static let shared = WKWebViewRulePatcher()
  var ruleList: WKContentRuleList?

  private override init() {
    super.init()
    swizzle()
  }

  private func swizzle() {
    let cls = WKWebView.self
    let orig = class_getInstanceMethod(cls, #selector(WKWebView.init(frame:configuration:)))
    let patched = class_getInstanceMethod(cls, #selector(WKWebView.pk_init(frame:configuration:)))
    if let o = orig, let p = patched {
      method_exchangeImplementations(o, p)
    }
  }
}

extension WKWebView {
  @objc func pk_init(frame: CGRect, configuration: WKWebViewConfiguration) -> WKWebView {
    // Call original (now swizzled to pk_init)
    let wv = pk_init(frame: frame, configuration: configuration)
    // Inject our content rule list if available
    if let rules = WKWebViewRulePatcher.shared.ruleList {
      wv.configuration.userContentController.add(rules)
    }
    return wv
  }
}
