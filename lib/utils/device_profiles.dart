import 'dart:math';

class DeviceProfile {
  final String name;
  final String userAgent;
  final String platform;
  final String vendor;
  final List<String> languages;
  final int hardwareConcurrency;
  final int deviceMemory;
  final int screenWidth;
  final int screenHeight;
  final double devicePixelRatio;
  final int maxTouchPoints;
  final String webglVendor;
  final String webglRenderer;
  final String timezone;
  final int timezoneOffset; // minutes from UTC (JST = -540)
  final String colorGamut;
  final int audioSampleRate;

  const DeviceProfile({
    required this.name,
    required this.userAgent,
    required this.platform,
    required this.vendor,
    required this.languages,
    required this.hardwareConcurrency,
    required this.deviceMemory,
    required this.screenWidth,
    required this.screenHeight,
    required this.devicePixelRatio,
    required this.maxTouchPoints,
    required this.webglVendor,
    required this.webglRenderer,
    required this.timezone,
    required this.timezoneOffset,
    required this.colorGamut,
    required this.audioSampleRate,
  });
}

// Updated UA strings - Chrome 136, iOS 18.x (as of mid-2025)
const List<DeviceProfile> kDeviceProfiles = [
  DeviceProfile(
    name: 'iPhone 16 Pro',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4.1 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 6,
    deviceMemory: 8,
    screenWidth: 402,
    screenHeight: 874,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Apple Inc.',
    webglRenderer: 'Apple GPU',
    timezone: 'Asia/Tokyo',
    timezoneOffset: -540,
    colorGamut: 'p3',
    audioSampleRate: 44100,
  ),
  DeviceProfile(
    name: 'iPhone 15 Pro',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_3_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3.2 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 6,
    deviceMemory: 8,
    screenWidth: 393,
    screenHeight: 852,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Apple Inc.',
    webglRenderer: 'Apple GPU',
    timezone: 'Asia/Tokyo',
    timezoneOffset: -540,
    colorGamut: 'p3',
    audioSampleRate: 44100,
  ),
  DeviceProfile(
    name: 'iPhone 15',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.7 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 6,
    deviceMemory: 6,
    screenWidth: 393,
    screenHeight: 852,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Apple Inc.',
    webglRenderer: 'Apple GPU',
    timezone: 'Asia/Tokyo',
    timezoneOffset: -540,
    colorGamut: 'p3',
    audioSampleRate: 44100,
  ),
  DeviceProfile(
    name: 'iPhone 14 Pro',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5.1 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 6,
    deviceMemory: 6,
    screenWidth: 393,
    screenHeight: 852,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Apple Inc.',
    webglRenderer: 'Apple GPU',
    timezone: 'Asia/Tokyo',
    timezoneOffset: -540,
    colorGamut: 'p3',
    audioSampleRate: 44100,
  ),
  DeviceProfile(
    name: 'iPhone 14',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 6,
    deviceMemory: 6,
    screenWidth: 390,
    screenHeight: 844,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Apple Inc.',
    webglRenderer: 'Apple GPU',
    timezone: 'Asia/Tokyo',
    timezoneOffset: -540,
    colorGamut: 'p3',
    audioSampleRate: 44100,
  ),
  DeviceProfile(
    name: 'iPhone 13',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_7_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'ja'],
    hardwareConcurrency: 6,
    deviceMemory: 4,
    screenWidth: 390,
    screenHeight: 844,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Apple Inc.',
    webglRenderer: 'Apple GPU',
    timezone: 'Asia/Tokyo',
    timezoneOffset: -540,
    colorGamut: 'p3',
    audioSampleRate: 44100,
  ),
  DeviceProfile(
    name: 'Samsung Galaxy S25',
    userAgent:
        'Mozilla/5.0 (Linux; Android 15; SM-S931B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.7103.60 Mobile Safari/537.36',
    platform: 'Linux armv81',
    vendor: 'Google Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 8,
    deviceMemory: 12,
    screenWidth: 411,
    screenHeight: 891,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Qualcomm',
    webglRenderer: 'Adreno (TM) 830',
    timezone: 'Asia/Tokyo',
    timezoneOffset: -540,
    colorGamut: 'p3',
    audioSampleRate: 48000,
  ),
  DeviceProfile(
    name: 'Samsung Galaxy S24',
    userAgent:
        'Mozilla/5.0 (Linux; Android 14; SM-S921B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.7049.111 Mobile Safari/537.36',
    platform: 'Linux armv81',
    vendor: 'Google Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 8,
    deviceMemory: 8,
    screenWidth: 411,
    screenHeight: 891,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Qualcomm',
    webglRenderer: 'Adreno (TM) 750',
    timezone: 'Asia/Tokyo',
    timezoneOffset: -540,
    colorGamut: 'p3',
    audioSampleRate: 48000,
  ),
  DeviceProfile(
    name: 'Google Pixel 9',
    userAgent:
        'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.7103.60 Mobile Safari/537.36',
    platform: 'Linux armv81',
    vendor: 'Google Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 9,
    deviceMemory: 12,
    screenWidth: 412,
    screenHeight: 892,
    devicePixelRatio: 2.625,
    maxTouchPoints: 5,
    webglVendor: 'ARM',
    webglRenderer: 'Immortalis-G925',
    timezone: 'Asia/Tokyo',
    timezoneOffset: -540,
    colorGamut: 'p3',
    audioSampleRate: 48000,
  ),
  DeviceProfile(
    name: 'Google Pixel 8',
    userAgent:
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.6998.39 Mobile Safari/537.36',
    platform: 'Linux armv81',
    vendor: 'Google Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 8,
    deviceMemory: 8,
    screenWidth: 412,
    screenHeight: 892,
    devicePixelRatio: 2.625,
    maxTouchPoints: 5,
    webglVendor: 'ARM',
    webglRenderer: 'Mali-G715',
    timezone: 'Asia/Tokyo',
    timezoneOffset: -540,
    colorGamut: 'p3',
    audioSampleRate: 48000,
  ),
];

final _rng = Random();

DeviceProfile randomProfile() {
  return kDeviceProfiles[_rng.nextInt(kDeviceProfiles.length)];
}

String buildAntiFingerprintScript(DeviceProfile p) {
  final langs = p.languages.map((l) => '"$l"').join(', ');
  // Random canvas noise seed per session
  final noiseSeed = _rng.nextInt(0xFFFF);
  // Slightly randomize screen availHeight (status bar varies 40-60px)
  final availH = p.screenHeight - 40 - _rng.nextInt(20);

  return '''
(function() {
  if (window.__fpPatched) return;
  window.__fpPatched = true;

  try {
    // ── 1. navigator overrides ─────────────────────────────────────────────
    const nav = navigator;

    function def(obj, prop, val) {
      try {
        Object.defineProperty(obj, prop, {
          get: () => val,
          configurable: true,
          enumerable: true,
        });
      } catch(e) {}
    }

    def(nav, 'platform',            '${p.platform}');
    def(nav, 'vendor',              '${p.vendor}');
    def(nav, 'userAgent',           '${p.userAgent}');
    def(nav, 'appVersion',          '5.0 (Mobile)');
    def(nav, 'hardwareConcurrency', ${p.hardwareConcurrency});
    def(nav, 'deviceMemory',        ${p.deviceMemory});
    def(nav, 'language',            '${p.languages.first}');
    def(nav, 'languages',           Object.freeze([$langs]));
    def(nav, 'maxTouchPoints',      ${p.maxTouchPoints});
    def(nav, 'doNotTrack',          null);

    // Remove automation flags
    def(nav, 'webdriver',           false);
    try { delete nav.__proto__.webdriver; } catch(e) {}

    // ── 2. screen ──────────────────────────────────────────────────────────
    def(screen, 'width',       ${p.screenWidth});
    def(screen, 'height',      ${p.screenHeight});
    def(screen, 'availWidth',  ${p.screenWidth});
    def(screen, 'availHeight', $availH);
    def(screen, 'colorDepth',  24);
    def(screen, 'pixelDepth',  24);
    def(window, 'devicePixelRatio', ${p.devicePixelRatio});
    def(window, 'outerWidth',  ${p.screenWidth});
    def(window, 'outerHeight', ${p.screenHeight});

    // ── 3. WebGL ───────────────────────────────────────────────────────────
    const glVendor   = '${p.webglVendor}';
    const glRenderer = '${p.webglRenderer}';

    [WebGLRenderingContext, typeof WebGL2RenderingContext !== 'undefined' ? WebGL2RenderingContext : null]
      .filter(Boolean)
      .forEach(function(ctx) {
        const orig = ctx.prototype.getParameter;
        ctx.prototype.getParameter = function(param) {
          if (param === 37445) return glVendor;
          if (param === 37446) return glRenderer;
          return orig.call(this, param);
        };
      });

    // ── 4. Canvas noise (per-session seed) ────────────────────────────────
    const SEED = $noiseSeed;
    function lcg(s) { return (s * 1664525 + 1013904223) & 0xffffffff; }

    (function patchCanvas() {
      const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
      const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;

      HTMLCanvasElement.prototype.toDataURL = function() {
        _addNoise(this);
        return origToDataURL.apply(this, arguments);
      };

      CanvasRenderingContext2D.prototype.getImageData = function(x, y, w, h) {
        const img = origGetImageData.call(this, x, y, w, h);
        let s = SEED;
        for (let i = 0; i < img.data.length; i += 4) {
          s = lcg(s);
          img.data[i]     = (img.data[i]     + (s & 1)) & 0xFF;
          img.data[i + 1] = (img.data[i + 1] + ((s >> 1) & 1)) & 0xFF;
        }
        return img;
      };

      function _addNoise(canvas) {
        try {
          const ctx2 = canvas.getContext('2d');
          if (!ctx2 || canvas.width === 0) return;
          const img = origGetImageData.call(ctx2, 0, 0, 1, 1);
          let s = SEED;
          img.data[0] = (img.data[0] + (s & 3)) & 0xFF;
          ctx2.putImageData(img, 0, 0);
        } catch(e) {}
      }
    })();

    // ── 5. AudioContext fingerprint ────────────────────────────────────────
    (function patchAudio() {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) return;
      const origCreate = AudioCtx.prototype.createOscillator;
      AudioCtx.prototype.createOscillator = function() {
        const osc = origCreate.call(this);
        const origConnect = osc.connect.bind(osc);
        osc.connect = function(dest) {
          // tiny pitch shift to change hash
          if (osc.frequency) osc.frequency.value += 0.0001;
          return origConnect(dest);
        };
        return osc;
      };

      // Randomise sampleRate slightly
      Object.defineProperty(AudioCtx.prototype, 'sampleRate', {
        get: function() { return ${p.audioSampleRate} + (SEED % 3); },
        configurable: true,
      });
    })();

    // ── 6. Timezone ────────────────────────────────────────────────────────
    (function patchTimezone() {
      const origDTF = Intl.DateTimeFormat;
      Intl.DateTimeFormat = function(locale, opts) {
        opts = opts || {};
        if (!opts.timeZone) opts.timeZone = '${p.timezone}';
        return new origDTF(locale, opts);
      };
      Intl.DateTimeFormat.prototype = origDTF.prototype;

      const origGetOffset = Date.prototype.getTimezoneOffset;
      Date.prototype.getTimezoneOffset = function() {
        return ${p.timezoneOffset};
      };
    })();

    // ── 7. Network & battery ───────────────────────────────────────────────
    def(nav, 'connection', {
      effectiveType: '4g',
      downlink: 8 + (SEED % 5),
      rtt: 40 + (SEED % 30),
      saveData: false,
      type: 'wifi',
    });

    if (!nav.getBattery) {
      nav.getBattery = () => Promise.resolve({
        charging: true,
        chargingTime: 0,
        dischargingTime: Infinity,
        level: 0.8 + (SEED % 20) / 100,
      });
    }

    // ── 8. Permissions API (prevent "denied" automation leak) ──────────────
    if (navigator.permissions) {
      const origQuery = navigator.permissions.query.bind(navigator.permissions);
      navigator.permissions.query = function(desc) {
        if (desc && (desc.name === 'notifications' || desc.name === 'push')) {
          return Promise.resolve({ state: 'prompt', onchange: null });
        }
        return origQuery(desc);
      };
    }

    // ── 9. Remove Chrome automation markers ───────────────────────────────
    try { delete window.cdc_adoQpoasnfa76pfcZLmcfl_Array; } catch(e) {}
    try { delete window.cdc_adoQpoasnfa76pfcZLmcfl_Promise; } catch(e) {}
    try { delete window.cdc_adoQpoasnfa76pfcZLmcfl_Symbol; } catch(e) {}
    window.chrome = { runtime: {}, app: {}, webstore: {} };

    // ── 10. Plugins (non-empty) ────────────────────────────────────────────
    def(nav, 'plugins', Object.freeze([
      { name: 'PDF Viewer',         filename: 'internal-pdf-viewer' },
      { name: 'Chrome PDF Viewer',  filename: 'internal-pdf-viewer' },
    ]));

    // ── 11. WebRTC IP leak prevention ─────────────────────────────────────
    // Block RTCPeerConnection to prevent ICE candidates from exposing real IP
    (function blockWebRTC() {
      try {
        const noop = function() {};
        const noopPC = function() {
          return {
            createOffer: () => Promise.reject(new Error('WebRTC disabled')),
            createAnswer: () => Promise.reject(new Error('WebRTC disabled')),
            setLocalDescription: noop,
            setRemoteDescription: noop,
            addIceCandidate: noop,
            close: noop,
            addEventListener: noop,
            removeEventListener: noop,
            getStats: () => Promise.resolve(new Map()),
            iceConnectionState: 'closed',
            iceGatheringState: 'complete',
            signalingState: 'closed',
          };
        };

        // Override all WebRTC constructors
        ['RTCPeerConnection', 'webkitRTCPeerConnection', 'mozRTCPeerConnection'].forEach(function(name) {
          if (window[name]) {
            window[name] = noopPC;
            window[name].prototype = {};
            Object.defineProperty(window, name, {
              get: () => noopPC,
              set: noop,
              configurable: false,
            });
          }
        });

        // Also patch getUserMedia to prevent mic/camera IP leak
        if (navigator.mediaDevices) {
          navigator.mediaDevices.getUserMedia = () => Promise.reject(new DOMException('NotAllowedError'));
          navigator.mediaDevices.enumerateDevices = () => Promise.resolve([]);
        }
        if (navigator.getUserMedia) navigator.getUserMedia = noop;
        if (navigator.webkitGetUserMedia) navigator.webkitGetUserMedia = noop;
        if (navigator.mozGetUserMedia) navigator.mozGetUserMedia = noop;
      } catch(e) {}
    })();

  } catch(e) {}
})();
''';
}

String buildAutoFillScript(String email, String password) {
  final safeEmail = email.replaceAll("'", "\\'");
  final safePass = password.replaceAll("'", "\\'");
  return '''
(function() {
  function setNativeValue(el, value) {
    const nativeInput = Object.getOwnPropertyDescriptor(
      el.tagName === 'INPUT' ? window.HTMLInputElement.prototype : window.HTMLTextAreaElement.prototype,
      'value'
    );
    if (nativeInput && nativeInput.set) {
      nativeInput.set.call(el, value);
    } else {
      el.value = value;
    }
    el.dispatchEvent(new Event('input',  { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new Event('blur',   { bubbles: true }));
  }

  function fillFirst(selectors, value) {
    for (const sel of selectors) {
      const el = document.querySelector(sel);
      if (el) { setNativeValue(el, value); return true; }
    }
    return false;
  }

  fillFirst([
    'input[type="email"]','input[name="email"]','input[name="loginEmail"]',
    'input[name="username"]','input[id*="email"]','input[placeholder*="メール"]',
    'input[placeholder*="email" i]',
  ], '$safeEmail');

  fillFirst([
    'input[type="password"]','input[name="password"]','input[name="loginPassword"]',
    'input[id*="pass"]',
  ], '$safePass');
})();
''';
}

String buildOtpAutoSubmitScript(String otp) {
  return '''
(function() {
  function setNativeValue(el, value) {
    const nativeInput = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
    if (nativeInput && nativeInput.set) {
      nativeInput.set.call(el, value);
    } else {
      el.value = value;
    }
    el.dispatchEvent(new Event('input',  { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
  }

  var otpSelectors = [
    'input#authCode',
    'input[name="dwfrm_factor2Auth_authCode"]',
    'input[name="passcode"]','input[name="otp"]','input[name="code"]',
    'input[id*="auth"]','input[id*="otp"]','input[id*="passcode"]',
    'input[placeholder*="パスコード"]','input[maxlength="6"]',
  ];

  var filled = false;
  for (var i = 0; i < otpSelectors.length; i++) {
    var el = document.querySelector(otpSelectors[i]);
    if (el) { setNativeValue(el, '$otp'); filled = true; break; }
  }

  if (!filled) {
    window.FlutterChannel.postMessage('{"type":"otpStatus","status":"noField"}');
    return;
  }
  window.FlutterChannel.postMessage('{"type":"otpStatus","status":"filled"}');

  setTimeout(function() {
    var submitEl =
      document.querySelector('a#authBtn') ||
      document.querySelector('a[id*="auth"]') ||
      document.querySelector('button[id*="auth"]');

    if (!submitEl) {
      var all = Array.from(document.querySelectorAll('button,input[type="submit"],a'));
      var kws = ['認証','送信','確認','次へ','submit','confirm'];
      for (var j = 0; j < all.length; j++) {
        var t = (all[j].textContent || all[j].value || '').trim();
        if (kws.some(function(k){ return t.indexOf(k) >= 0 || t.toLowerCase().indexOf(k) >= 0; })) {
          submitEl = all[j]; break;
        }
      }
    }

    if (submitEl) {
      submitEl.click();
      window.FlutterChannel.postMessage('{"type":"otpStatus","status":"submitted"}');
    } else {
      window.FlutterChannel.postMessage('{"type":"otpStatus","status":"noButton"}');
    }
  }, 600);
})();
''';
}

String buildOtpFillScript(String otp) {
  return '''
(function() {
  function fill(sel, val) {
    var el = document.querySelector(sel);
    if (!el) return false;
    var nv = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
    if (nv && nv.set) nv.set.call(el, val);
    else el.value = val;
    el.dispatchEvent(new Event('input',  { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
  }
  var sels = [
    'input[name="passcode"]','input[name="otp"]','input[name="code"]','input[name="token"]',
    'input[id*="otp"]','input[id*="code"]','input[placeholder*="認証"]',
    'input[placeholder*="コード"]','input[placeholder*="パスコード"]',
    'input[maxlength="6"]','input[maxlength="4"]',
  ];
  for (var s of sels) { if (fill(s, '$otp')) break; }
})();
''';
}

String buildOtpErrorDetectScript() {
  return '''
(function() {
  var kws = [
    'パスコードが正しくありません','パスコードが違','正しくない',
    'コードが正しくありません','無効','期限','有効期限',
    'incorrect','invalid','expired','wrong code',
  ];
  var text = document.body ? document.body.innerText : '';
  if (kws.some(function(k){ return text.includes(k); })) {
    window.FlutterChannel.postMessage(JSON.stringify({type:'otpError',detected:true}));
  }
})();
''';
}
