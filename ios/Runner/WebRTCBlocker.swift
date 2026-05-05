import Foundation
import WebKit

// Disables WebRTC in every WKWebView by swizzling the designated initializer
// so our block script is injected before any page JS runs.
//
// WKWebViewConfiguration.init is a plain ObjC init that returns self — safe to swizzle.
// The script runs at .atDocumentStart so it always beats page JS.

private let kWebRTCBlockJS = """
(function(){
  'use strict';
  var noop = function(){};

  // Fake RTCPeerConnection that never leaks ICE candidates
  function FakeRTCPC(){
    if(!(this instanceof FakeRTCPC)) return new FakeRTCPC();
    this.onicecandidate = null;
    this.ontrack = null;
    this.ondatachannel = null;
  }
  FakeRTCPC.prototype = {
    createOffer:           function(){ return Promise.reject(new DOMException('WebRTC blocked')); },
    createAnswer:          function(){ return Promise.reject(new DOMException('WebRTC blocked')); },
    setLocalDescription:   function(){ return Promise.resolve(); },
    setRemoteDescription:  function(){ return Promise.resolve(); },
    addIceCandidate:       function(){ return Promise.resolve(); },
    getStats:              function(){ return Promise.resolve([]); },
    close: noop, addEventListener: noop, removeEventListener: noop,
    getSenders:            function(){ return []; },
    getReceivers:          function(){ return []; },
    getTransceivers:       function(){ return []; },
    createDataChannel:     function(){ return {}; },
    get iceConnectionState(){ return 'closed'; },
    get iceGatheringState() { return 'complete'; },
    get signalingState()    { return 'closed'; },
    get connectionState()   { return 'closed'; },
    get localDescription()  { return null; },
    get remoteDescription() { return null; },
  };
  FakeRTCPC.generateCertificate = function(){ return Promise.reject(new Error('blocked')); };

  ['RTCPeerConnection','webkitRTCPeerConnection','mozRTCPeerConnection'].forEach(function(n){
    try { Object.defineProperty(window, n, { value: FakeRTCPC, writable:false, configurable:false }); } catch(e){}
  });

  // Block media devices (also used for IP fingerprinting)
  try {
    Object.defineProperty(navigator, 'mediaDevices', {
      get: function(){
        return {
          getUserMedia:            function(){ return Promise.reject(new DOMException('NotAllowedError')); },
          enumerateDevices:        function(){ return Promise.resolve([]); },
          getSupportedConstraints: function(){ return {}; },
          addEventListener:        noop,
          removeEventListener:     noop,
        };
      },
      configurable: false,
    });
  } catch(e){}

  ['getUserMedia','webkitGetUserMedia','mozGetUserMedia'].forEach(function(n){
    try { Object.defineProperty(navigator, n, { value: noop, configurable:false }); } catch(e){}
  });
})();
"""

class WebRTCBlocker {
  static let shared = WebRTCBlocker()
  private var installed = false
  private init() {}

  func install() {
    guard !installed else { return }
    installed = true

    let wkClass: AnyClass = WKWebView.self

    // Swizzle -[WKWebView initWithFrame:configuration:]
    let origSel = #selector(WKWebView.init(frame:configuration:))
    let swizSel = #selector(WKWebView.webrtcBlocker_initWithFrame(_:configuration:))

    guard
      let origMethod = class_getInstanceMethod(wkClass, origSel),
      let swizMethod = class_getInstanceMethod(wkClass, swizSel)
    else { return }

    method_exchangeImplementations(origMethod, swizMethod)
  }
}

extension WKWebView {
  @objc func webrtcBlocker_initWithFrame(_ frame: CGRect,
                                         configuration: WKWebViewConfiguration) -> WKWebView {
    // Inject before calling original init so the script is part of the config
    let script = WKUserScript(
      source: kWebRTCBlockJS,
      injectionTime: .atDocumentStart,
      forMainFrameOnly: false
    )
    configuration.userContentController.addUserScript(script)

    // Call original (swizzled — names are exchanged)
    return webrtcBlocker_initWithFrame(frame, configuration: configuration)
  }
}
