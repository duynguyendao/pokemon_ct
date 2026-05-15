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

// ─── Base devices × iOS versions = expanded profile pool ────────────────────
// Chỉ Safari iOS — WKWebView không gửi được Sec-CH-UA headers nên Chrome UA sẽ
// bị detect ngay.
class _BaseDevice {
  final String name;
  final int screenWidth;
  final int screenHeight;
  final int memory;
  final int hwConcurrency;
  final double devicePixelRatio;
  final List<String> iosVersions;
  const _BaseDevice({
    required this.name,
    required this.screenWidth,
    required this.screenHeight,
    required this.memory,
    this.hwConcurrency = 4,
    this.devicePixelRatio = 3.0,
    required this.iosVersions,
  });
}

const List<_BaseDevice> _baseDevices = [
  // iPhone 16 series (iOS 18 only)
  _BaseDevice(
    name: 'iPhone 16 Pro Max',
    screenWidth: 440, screenHeight: 956, memory: 8,
    iosVersions: ['18.5', '18.4.1', '18.4', '18.3.2', '18.3'],
  ),
  _BaseDevice(
    name: 'iPhone 16 Pro',
    screenWidth: 402, screenHeight: 874, memory: 8,
    iosVersions: ['18.5', '18.4.1', '18.4', '18.3.2', '18.3'],
  ),
  _BaseDevice(
    name: 'iPhone 16 Plus',
    screenWidth: 430, screenHeight: 932, memory: 8,
    iosVersions: ['18.5', '18.4', '18.3.1', '18.3'],
  ),
  _BaseDevice(
    name: 'iPhone 16',
    screenWidth: 393, screenHeight: 852, memory: 8,
    iosVersions: ['18.5', '18.4.1', '18.4', '18.3'],
  ),
  // iPhone 15 series (iOS 17-18)
  _BaseDevice(
    name: 'iPhone 15 Pro Max',
    screenWidth: 430, screenHeight: 932, memory: 8,
    iosVersions: ['18.4', '18.3', '18.2', '17.7.2', '17.6.1'],
  ),
  _BaseDevice(
    name: 'iPhone 15 Pro',
    screenWidth: 393, screenHeight: 852, memory: 8,
    iosVersions: ['18.4', '18.3.2', '18.2.1', '17.7.1', '17.6'],
  ),
  _BaseDevice(
    name: 'iPhone 15 Plus',
    screenWidth: 430, screenHeight: 932, memory: 6,
    iosVersions: ['18.3', '18.2', '17.7', '17.6.1'],
  ),
  _BaseDevice(
    name: 'iPhone 15',
    screenWidth: 393, screenHeight: 852, memory: 6,
    iosVersions: ['18.3', '18.2', '17.7.2', '17.6'],
  ),
  // iPhone 14 series (iOS 17-18)
  _BaseDevice(
    name: 'iPhone 14 Pro Max',
    screenWidth: 430, screenHeight: 932, memory: 6,
    iosVersions: ['18.3', '18.2', '17.7.1', '17.6.1'],
  ),
  _BaseDevice(
    name: 'iPhone 14 Pro',
    screenWidth: 393, screenHeight: 852, memory: 6,
    iosVersions: ['18.3.1', '18.2', '17.7', '17.5.1'],
  ),
  _BaseDevice(
    name: 'iPhone 14 Plus',
    screenWidth: 428, screenHeight: 926, memory: 6,
    iosVersions: ['18.2', '17.7', '17.6'],
  ),
  _BaseDevice(
    name: 'iPhone 14',
    screenWidth: 390, screenHeight: 844, memory: 6,
    iosVersions: ['18.2', '17.6.1', '17.5.1', '17.4.1'],
  ),
  // iPhone 13 series (iOS 16-18)
  _BaseDevice(
    name: 'iPhone 13 Pro Max',
    screenWidth: 428, screenHeight: 926, memory: 6,
    iosVersions: ['18.1', '17.6', '17.4', '16.7.10'],
  ),
  _BaseDevice(
    name: 'iPhone 13 Pro',
    screenWidth: 390, screenHeight: 844, memory: 6,
    iosVersions: ['18.1', '17.5', '17.3', '16.7.10'],
  ),
  _BaseDevice(
    name: 'iPhone 13',
    screenWidth: 390, screenHeight: 844, memory: 4,
    iosVersions: ['18.0', '17.6.1', '17.4.1', '16.7.8'],
  ),
  _BaseDevice(
    name: 'iPhone 13 mini',
    screenWidth: 375, screenHeight: 812, memory: 4,
    iosVersions: ['17.7', '17.5', '16.7.10'],
  ),
  // iPhone 12 series (iOS 16-18)
  _BaseDevice(
    name: 'iPhone 12 Pro Max',
    screenWidth: 428, screenHeight: 926, memory: 6,
    iosVersions: ['18.0', '17.6', '17.4', '16.7.10'],
  ),
  _BaseDevice(
    name: 'iPhone 12 Pro',
    screenWidth: 390, screenHeight: 844, memory: 6,
    iosVersions: ['17.6', '17.4', '16.7.10'],
  ),
  _BaseDevice(
    name: 'iPhone 12',
    screenWidth: 390, screenHeight: 844, memory: 4,
    iosVersions: ['17.5.1', '17.4.1', '16.7.8'],
  ),
  _BaseDevice(
    name: 'iPhone 12 mini',
    screenWidth: 375, screenHeight: 812, memory: 4,
    iosVersions: ['17.4', '17.2', '16.7.10'],
  ),
  // iPhone 11 series (iOS 16-17 mostly)
  _BaseDevice(
    name: 'iPhone 11 Pro Max',
    screenWidth: 414, screenHeight: 896, memory: 4,
    iosVersions: ['17.4', '16.7.10', '16.7.8'],
  ),
  _BaseDevice(
    name: 'iPhone 11 Pro',
    screenWidth: 375, screenHeight: 812, memory: 4,
    iosVersions: ['17.5', '16.7.10', '16.7.8'],
  ),
  _BaseDevice(
    name: 'iPhone 11',
    screenWidth: 414, screenHeight: 896, memory: 4,
    iosVersions: ['17.4.1', '17.3', '16.7.10'],
  ),
  // iPhone XS/XR/X series (iOS 16 max)
  _BaseDevice(
    name: 'iPhone XS Max',
    screenWidth: 414, screenHeight: 896, memory: 4,
    iosVersions: ['16.7.10', '16.7.8', '16.7.5', '16.6.1'],
  ),
  _BaseDevice(
    name: 'iPhone XS',
    screenWidth: 375, screenHeight: 812, memory: 4,
    iosVersions: ['16.7.10', '16.7.8', '16.7.5', '16.6.1'],
  ),
  _BaseDevice(
    name: 'iPhone XR',
    screenWidth: 414, screenHeight: 896, memory: 3,
    devicePixelRatio: 2.0,
    iosVersions: ['16.7.10', '16.7.8', '16.7.5', '16.6.1'],
  ),
  _BaseDevice(
    name: 'iPhone X',
    screenWidth: 375, screenHeight: 812, memory: 3,
    hwConcurrency: 2,
    iosVersions: ['16.7.10', '16.7.8', '16.7.5', '16.6.1'],
  ),
  // iPhone 8 series (iOS 16 max)
  _BaseDevice(
    name: 'iPhone 8 Plus',
    screenWidth: 414, screenHeight: 736, memory: 3,
    hwConcurrency: 2,
    iosVersions: ['16.7.10', '16.7.8', '16.7.5', '16.6.1'],
  ),
  _BaseDevice(
    name: 'iPhone 8',
    screenWidth: 375, screenHeight: 667, memory: 2,
    devicePixelRatio: 2.0, hwConcurrency: 2,
    iosVersions: ['16.7.10', '16.7.8', '16.7.5', '16.6.1'],
  ),
  // iPhone 7 series (iOS 15 max)
  _BaseDevice(
    name: 'iPhone 7 Plus',
    screenWidth: 414, screenHeight: 736, memory: 3,
    hwConcurrency: 2,
    iosVersions: ['15.8.3', '15.8.2', '15.7.9', '15.6.1'],
  ),
  _BaseDevice(
    name: 'iPhone 7',
    screenWidth: 375, screenHeight: 667, memory: 2,
    devicePixelRatio: 2.0, hwConcurrency: 2,
    iosVersions: ['15.8.3', '15.8.2', '15.7.9', '15.6.1'],
  ),
  // iPhone 6s series (iOS 15 max)
  _BaseDevice(
    name: 'iPhone 6s Plus',
    screenWidth: 414, screenHeight: 736, memory: 2,
    hwConcurrency: 2,
    iosVersions: ['15.8.3', '15.8.2', '15.7.9', '15.6.1'],
  ),
  _BaseDevice(
    name: 'iPhone 6s',
    screenWidth: 375, screenHeight: 667, memory: 2,
    devicePixelRatio: 2.0, hwConcurrency: 2,
    iosVersions: ['15.8.3', '15.8.2', '15.7.9', '15.6.1'],
  ),
  // iPhone SE (DPR = 2.0, không phải 3.0 như các iPhone khác)
  _BaseDevice(
    name: 'iPhone SE (3rd gen)',
    screenWidth: 375, screenHeight: 667, memory: 4,
    devicePixelRatio: 2.0,
    iosVersions: ['18.2', '17.6', '17.4', '16.7.10'],
  ),
  _BaseDevice(
    name: 'iPhone SE (2nd gen)',
    screenWidth: 375, screenHeight: 667, memory: 3,
    devicePixelRatio: 2.0,
    iosVersions: ['17.4', '16.7.10', '16.7.8'],
  ),
  _BaseDevice(
    name: 'iPhone SE (1st gen)',
    screenWidth: 320, screenHeight: 568, memory: 2,
    devicePixelRatio: 2.0, hwConcurrency: 2,
    iosVersions: ['15.8.3', '15.8.2', '15.7.9', '15.6.1'],
  ),
];

List<DeviceProfile> _generateProfiles() {
  final result = <DeviceProfile>[];
  for (final dev in _baseDevices) {
    for (final ios in dev.iosVersions) {
      final iosUnder = ios.replaceAll('.', '_');
      result.add(DeviceProfile(
        name: '${dev.name} · iOS $ios',
        userAgent:
            'Mozilla/5.0 (iPhone; CPU iPhone OS $iosUnder like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$ios Mobile/15E148 Safari/604.1',
        platform: 'iPhone',
        vendor: 'Apple Computer, Inc.',
        languages: const ['ja-JP', 'ja', 'en-US'],
        hardwareConcurrency: dev.hwConcurrency,
        deviceMemory: dev.memory,
        screenWidth: dev.screenWidth,
        screenHeight: dev.screenHeight,
        devicePixelRatio: dev.devicePixelRatio,
        maxTouchPoints: 5,
        webglVendor: 'Apple Inc.',
        webglRenderer: 'Apple GPU',
        timezone: 'Asia/Tokyo',
        timezoneOffset: -540,
        colorGamut: 'p3',
        audioSampleRate: 44100,
      ));
    }
  }
  return List.unmodifiable(result);
}

final List<DeviceProfile> kDeviceProfiles = _generateProfiles();

final _rng = Random();

DeviceProfile randomProfile({DeviceProfile? except}) {
  if (except == null || kDeviceProfiles.length <= 1) {
    return kDeviceProfiles[_rng.nextInt(kDeviceProfiles.length)];
  }
  // Loại bỏ profile cũ để đảm bảo UA thực sự đổi
  final pool = kDeviceProfiles.where((p) => p.name != except.name).toList();
  return pool[_rng.nextInt(pool.length)];
}

String buildAntiFingerprintScript(DeviceProfile p) {
  final langs = p.languages.map((l) => '"$l"').join(', ');
  final noiseSeed = _rng.nextInt(0xFFFF);
  final availH = p.screenHeight - 40 - _rng.nextInt(20);

  // Tất cả profile giờ là Safari iOS — script hardcode behavior phù hợp
  // appVersion = phần sau "Mozilla/" trong UA
  final appVersion = p.userAgent.startsWith('Mozilla/')
      ? p.userAgent.substring('Mozilla/'.length)
      : '5.0 (Mobile)';

  // Safari iOS: PluginArray rỗng
  const pluginsJs = 'def(nav, "plugins", Object.freeze([]));';

  // Safari không có window.chrome
  const chromeJs = '''try { delete window.chrome; } catch(e) {}
    Object.defineProperty(window, 'chrome', { get: () => undefined, configurable: true, enumerable: false });''';

  // Safari iOS có navigator.standalone
  const standaloneJs = 'def(nav, "standalone", false);';

  return '''
(function() {
  var _k='_wk0';
  try{if(window[_k])return;Object.defineProperty(window,_k,{value:1,enumerable:false,configurable:false,writable:false});}catch(e){}

  // ── 0. Wipe storage NGAY trước khi page scripts đọc được ────────────────
  try{localStorage.clear();}catch(e){}
  try{sessionStorage.clear();}catch(e){}
  try{
    if(indexedDB && indexedDB.databases){
      indexedDB.databases().then(function(dbs){
        dbs.forEach(function(db){try{indexedDB.deleteDatabase(db.name);}catch(e){}});
      });
    }
  }catch(e){}

  try {
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

    // Helper: pin function.toString để không lộ patch
    function nativeStr(fn, name) {
      try {
        Object.defineProperty(fn, 'toString', {
          value: function(){ return 'function ' + (name || fn.name || '') + '() { [native code] }'; },
          writable: false, configurable: true,
        });
      } catch(e) {}
    }

    // ── 1. navigator ───────────────────────────────────────────────────────
    def(nav, 'platform',            '${p.platform}');
    def(nav, 'vendor',              '${p.vendor}');
    def(nav, 'userAgent',           '${p.userAgent}');
    def(nav, 'appVersion',          '$appVersion');
    def(nav, 'appName',             'Netscape');
    def(nav, 'product',             'Gecko');
    def(nav, 'hardwareConcurrency', ${p.hardwareConcurrency});
    // Safari iOS KHÔNG hỗ trợ navigator.deviceMemory — phải để undefined
    try { delete nav.deviceMemory; } catch(e) {}
    try { Object.defineProperty(nav, 'deviceMemory', { get: () => undefined, configurable: true }); } catch(e) {}
    def(nav, 'language',            '${p.languages.first}');
    def(nav, 'languages',           Object.freeze([$langs]));
    def(nav, 'maxTouchPoints',      ${p.maxTouchPoints});
    def(nav, 'doNotTrack',          null);
    def(nav, 'cookieEnabled',       true);
    def(nav, 'onLine',              true);
    // webdriver: real browsers don't define this
    try { delete nav.__proto__.webdriver; } catch(e) {}
    try { Object.defineProperty(nav, 'webdriver', { get: () => undefined, configurable: true, enumerable: false }); } catch(e) {}
    $standaloneJs

    // ── 2. screen ──────────────────────────────────────────────────────────
    def(screen, 'width',       ${p.screenWidth});
    def(screen, 'height',      ${p.screenHeight});
    def(screen, 'availWidth',  ${p.screenWidth});
    def(screen, 'availHeight', $availH);
    def(screen, 'availLeft',   0);
    def(screen, 'availTop',    0);
    def(screen, 'colorDepth',  24);
    def(screen, 'pixelDepth',  24);
    def(window, 'devicePixelRatio', ${p.devicePixelRatio});
    def(window, 'outerWidth',  ${p.screenWidth});
    def(window, 'outerHeight', ${p.screenHeight});
    def(window, 'innerWidth',  ${p.screenWidth});
    def(window, 'innerHeight', $availH);
    def(window, 'screenX',     0);
    def(window, 'screenY',     0);
    def(window, 'screenLeft',  0);
    def(window, 'screenTop',   0);

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
          // UNMASKED_VENDOR_WEBGL = 0x9245, UNMASKED_RENDERER_WEBGL = 0x9246
          if (param === 0x9245) return glVendor;
          if (param === 0x9246) return glRenderer;
          return orig.call(this, param);
        };
        nativeStr(ctx.prototype.getParameter, 'getParameter');
        // getExtension WEBGL_debug_renderer_info → consistent
        const origExt = ctx.prototype.getExtension;
        ctx.prototype.getExtension = function(name) {
          return origExt.call(this, name);
        };
        nativeStr(ctx.prototype.getExtension, 'getExtension');
      });

    // ── 4. Canvas noise (toDataURL, toBlob, getImageData) ─────────────────
    const SEED = $noiseSeed;
    function lcg(s) { return (s * 1664525 + 1013904223) & 0xffffffff; }

    (function patchCanvas() {
      const origToDataURL    = HTMLCanvasElement.prototype.toDataURL;
      const origToBlob       = HTMLCanvasElement.prototype.toBlob;
      const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;

      function _addNoise(canvas) {
        try {
          const ctx2 = canvas.getContext('2d');
          if (!ctx2 || canvas.width === 0 || canvas.height === 0) return;
          const img = origGetImageData.call(ctx2, 0, 0, Math.min(1, canvas.width), Math.min(1, canvas.height));
          let s = SEED;
          img.data[0] = (img.data[0] + (s & 3)) & 0xFF;
          ctx2.putImageData(img, 0, 0);
        } catch(e) {}
      }

      HTMLCanvasElement.prototype.toDataURL = function() {
        _addNoise(this);
        return origToDataURL.apply(this, arguments);
      };
      nativeStr(HTMLCanvasElement.prototype.toDataURL, 'toDataURL');

      HTMLCanvasElement.prototype.toBlob = function() {
        _addNoise(this);
        return origToBlob.apply(this, arguments);
      };
      nativeStr(HTMLCanvasElement.prototype.toBlob, 'toBlob');

      CanvasRenderingContext2D.prototype.getImageData = function(x, y, w, h) {
        const img = origGetImageData.call(this, x, y, w, h);
        if (img.data.length >= 4) img.data[0] = (img.data[0] + (SEED & 3)) & 0xFF;
        return img;
      };
      nativeStr(CanvasRenderingContext2D.prototype.getImageData, 'getImageData');
    })();

    // ── 4b. OffscreenCanvas noise (Safari iOS 16.4+ has it) ────────────────
    (function patchOffscreen() {
      if (typeof OffscreenCanvas === 'undefined') return;
      try {
        const origConvert = OffscreenCanvas.prototype.convertToBlob;
        if (origConvert) {
          OffscreenCanvas.prototype.convertToBlob = function() {
            return origConvert.apply(this, arguments);
          };
          nativeStr(OffscreenCanvas.prototype.convertToBlob, 'convertToBlob');
        }
      } catch(e) {}
    })();

    // ── 5. AudioContext noise ─────────────────────────────────────────────
    (function patchAudio() {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) return;
      const origCreate = AudioCtx.prototype.createOscillator;
      AudioCtx.prototype.createOscillator = function() {
        const osc = origCreate.call(this);
        const origConnect = osc.connect.bind(osc);
        osc.connect = function(dest) {
          if (osc.frequency) osc.frequency.value += 0.0001;
          return origConnect(dest);
        };
        return osc;
      };
      Object.defineProperty(AudioCtx.prototype, 'sampleRate', {
        get: function() { return ${p.audioSampleRate} + (SEED % 3); },
        configurable: true,
      });
      // AnalyserNode.getFloatFrequencyData / getByteFrequencyData noise
      if (window.AnalyserNode) {
        const origFloat = AnalyserNode.prototype.getFloatFrequencyData;
        AnalyserNode.prototype.getFloatFrequencyData = function(arr) {
          origFloat.call(this, arr);
          let s = SEED;
          for (let i = 0; i < arr.length; i++) {
            s = lcg(s);
            arr[i] = arr[i] + ((s & 0xFF) / 0xFFFF) * 0.0001;
          }
        };
        nativeStr(AnalyserNode.prototype.getFloatFrequencyData, 'getFloatFrequencyData');
      }
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
      Date.prototype.getTimezoneOffset = function() { return ${p.timezoneOffset}; };
      nativeStr(Date.prototype.getTimezoneOffset, 'getTimezoneOffset');
    })();

    // ── 7. Network & battery ───────────────────────────────────────────────
    if (nav.connection) {
      def(nav, 'connection', {
        effectiveType: '4g',
        downlink: 8 + (SEED % 5),
        rtt: 40 + (SEED % 30),
        saveData: false,
        type: 'cellular',
      });
    }
    if (!nav.getBattery) {
      nav.getBattery = () => Promise.resolve({
        charging: true, chargingTime: 0, dischargingTime: Infinity,
        level: 0.8 + (SEED % 20) / 100,
      });
    }

    // ── 8. Permissions ─────────────────────────────────────────────────────
    if (navigator.permissions) {
      const origQuery = navigator.permissions.query.bind(navigator.permissions);
      navigator.permissions.query = function(desc) {
        if (desc && (desc.name === 'notifications' || desc.name === 'push')) {
          return Promise.resolve({ state: 'prompt', onchange: null });
        }
        return origQuery(desc);
      };
      nativeStr(navigator.permissions.query, 'query');
    }

    // ── 9. chrome object — Safari không có ────────────────────────────────
    try { delete window.cdc_adoQpoasnfa76pfcZLmcfl_Array; } catch(e) {}
    try { delete window.cdc_adoQpoasnfa76pfcZLmcfl_Promise; } catch(e) {}
    try { delete window.cdc_adoQpoasnfa76pfcZLmcfl_Symbol; } catch(e) {}
    $chromeJs

    // ── 10. Plugins — Safari iOS rỗng ─────────────────────────────────────
    $pluginsJs
    try { def(nav, 'mimeTypes', Object.freeze([])); } catch(e) {}

    // ── 11. matchMedia — color gamut + mobile pointer/hover ───────────────
    (function patchMatchMedia() {
      const origMQ = window.matchMedia;
      if (!origMQ) return;
      window.matchMedia = function(query) {
        const result = origMQ.call(window, query);
        const q = query.toLowerCase();
        try {
          if (q.includes('color-gamut')) {
            const gamut = '${p.colorGamut}';
            const matches = (gamut === 'p3' && q.includes('p3')) ||
                            (gamut === 'srgb' && q.includes('srgb'));
            Object.defineProperty(result, 'matches', { get: () => matches, configurable: true });
          } else if (q.includes('pointer')) {
            Object.defineProperty(result, 'matches', { get: () => q.includes('coarse'), configurable: true });
          } else if (q.includes('hover')) {
            Object.defineProperty(result, 'matches', { get: () => q.includes('none'), configurable: true });
          } else if (q.includes('prefers-color-scheme')) {
            Object.defineProperty(result, 'matches', { get: () => q.includes('light'), configurable: true });
          }
        } catch(e) {}
        return result;
      };
      nativeStr(window.matchMedia, 'matchMedia');
    })();

    // ── 12. userAgentData — Safari iOS KHÔNG có, đảm bảo undefined ────────
    try { delete nav.userAgentData; } catch(e) {}
    try { Object.defineProperty(nav, 'userAgentData', { get: () => undefined, configurable: true }); } catch(e) {}

    // ── 13. Block RTCPeerConnection (IP leak) ──────────────────────────────
    try { Object.defineProperty(window,'RTCPeerConnection',       {value:undefined,configurable:true}); } catch(e) {}
    try { Object.defineProperty(window,'webkitRTCPeerConnection', {value:undefined,configurable:true}); } catch(e) {}
    try { Object.defineProperty(window,'RTCIceCandidate',         {value:undefined,configurable:true}); } catch(e) {}
    try { Object.defineProperty(window,'RTCSessionDescription',   {value:undefined,configurable:true}); } catch(e) {}

    // ── 14. performance.memory (Chrome only) — Safari không có ────────────
    try { delete window.performance.memory; } catch(e) {}
    try { Object.defineProperty(window.performance, 'memory', { get: () => undefined, configurable: true }); } catch(e) {}

    // ── 15. document.visibilityState — always visible ──────────────────────
    try { Object.defineProperty(document,'visibilityState',{get:()=>'visible',configurable:true}); } catch(e) {}
    try { Object.defineProperty(document,'hidden',         {get:()=>false,    configurable:true}); } catch(e) {}

    // ── 16. pdfViewerEnabled — Safari iOS: false ──────────────────────────
    def(nav, 'pdfViewerEnabled', false);

    // ── 17. screen.orientation ────────────────────────────────────────────
    try {
      Object.defineProperty(screen,'orientation',{
        get:()=>({type:'portrait-primary',angle:0,onchange:null}), configurable:true
      });
    } catch(e) {}

    // ── 18. MediaDevices — iOS Safari: trả empty list khi chưa cấp quyền ─
    if (nav.mediaDevices) {
      try {
        nav.mediaDevices.enumerateDevices = function() {
          return Promise.resolve([]);
        };
        nativeStr(nav.mediaDevices.enumerateDevices, 'enumerateDevices');
      } catch(e) {}
      // Block getUserMedia — không cho lộ device info
      try {
        nav.mediaDevices.getUserMedia = function() {
          return Promise.reject(new DOMException('Permission denied', 'NotAllowedError'));
        };
        nativeStr(nav.mediaDevices.getUserMedia, 'getUserMedia');
      } catch(e) {}
    }

    // ── 19. Speech synthesis voices — iOS Safari có set voices đặc trưng ─
    (function patchSpeech() {
      if (typeof speechSynthesis === 'undefined') return;
      // iOS Safari thường có ~36 voices, KHÔNG để empty (bị flag là headless)
      const iosVoices = [
        { name: 'Kyoko', lang: 'ja-JP', localService: true, default: false, voiceURI: 'com.apple.voice.compact.ja-JP.Kyoko' },
        { name: 'Otoya', lang: 'ja-JP', localService: true, default: false, voiceURI: 'com.apple.voice.compact.ja-JP.Otoya' },
        { name: 'Samantha', lang: 'en-US', localService: true, default: true, voiceURI: 'com.apple.voice.compact.en-US.Samantha' },
        { name: 'Daniel', lang: 'en-GB', localService: true, default: false, voiceURI: 'com.apple.voice.compact.en-GB.Daniel' },
        { name: 'Karen', lang: 'en-AU', localService: true, default: false, voiceURI: 'com.apple.voice.compact.en-AU.Karen' },
        { name: 'Moira', lang: 'en-IE', localService: true, default: false, voiceURI: 'com.apple.voice.compact.en-IE.Moira' },
        { name: 'Tessa', lang: 'en-ZA', localService: true, default: false, voiceURI: 'com.apple.voice.compact.en-ZA.Tessa' },
        { name: 'Rishi', lang: 'en-IN', localService: true, default: false, voiceURI: 'com.apple.voice.compact.en-IN.Rishi' },
        { name: 'Yuna', lang: 'ko-KR', localService: true, default: false, voiceURI: 'com.apple.voice.compact.ko-KR.Yuna' },
        { name: 'Tingting', lang: 'zh-CN', localService: true, default: false, voiceURI: 'com.apple.voice.compact.zh-CN.Tingting' },
      ];
      try {
        speechSynthesis.getVoices = function() { return iosVoices; };
        nativeStr(speechSynthesis.getVoices, 'getVoices');
      } catch(e) {}
    })();

    // ── 20. ClientRects sub-pixel jitter ──────────────────────────────────
    (function patchRects() {
      const origGBCR = Element.prototype.getBoundingClientRect;
      const origGCR  = Element.prototype.getClientRects;
      Element.prototype.getBoundingClientRect = function() {
        const r = origGBCR.call(this);
        const j = ((SEED % 100) / 100000);
        return {
          x: r.x + j, y: r.y + j,
          top: r.top + j, left: r.left + j,
          right: r.right + j, bottom: r.bottom + j,
          width: r.width, height: r.height,
          toJSON: function(){ return this; },
        };
      };
      nativeStr(Element.prototype.getBoundingClientRect, 'getBoundingClientRect');
      Element.prototype.getClientRects = function() {
        return origGCR.call(this);
      };
      nativeStr(Element.prototype.getClientRects, 'getClientRects');
    })();

    // ── 21. WebGPU — Safari iOS chưa có (đảm bảo undefined) ───────────────
    try { delete nav.gpu; } catch(e) {}
    try { Object.defineProperty(nav, 'gpu', { get: () => undefined, configurable: true }); } catch(e) {}

    // ── 22. Web APIs Safari iOS không có ─────────────────────────────────
    try { Object.defineProperty(nav, 'usb',       { get: () => undefined, configurable: true }); } catch(e) {}
    try { Object.defineProperty(nav, 'bluetooth', { get: () => undefined, configurable: true }); } catch(e) {}
    try { Object.defineProperty(nav, 'serial',    { get: () => undefined, configurable: true }); } catch(e) {}
    try { Object.defineProperty(nav, 'hid',       { get: () => undefined, configurable: true }); } catch(e) {}
    try { Object.defineProperty(nav, 'locks',     { get: () => undefined, configurable: true }); } catch(e) {}

    // ── 23. DeviceMotion / DeviceOrientation — iOS yêu cầu permission ─────
    try {
      if (window.DeviceMotionEvent && !window.DeviceMotionEvent.requestPermission) {
        window.DeviceMotionEvent.requestPermission = function() {
          return Promise.resolve('granted');
        };
      }
      if (window.DeviceOrientationEvent && !window.DeviceOrientationEvent.requestPermission) {
        window.DeviceOrientationEvent.requestPermission = function() {
          return Promise.resolve('granted');
        };
      }
    } catch(e) {}

    // ── 24. Touch events — đảm bảo có mặt cho mobile ─────────────────────
    try { window.ontouchstart = null; } catch(e) {}
    try { window.ontouchmove = null; } catch(e) {}
    try { window.ontouchend = null; } catch(e) {}

    // ── 25. Function.prototype.toString — hide patched functions ──────────
    (function() {
      try {
        var origTS = Function.prototype.toString;
        function patched() { return origTS.call(this); }
        Object.defineProperty(Function.prototype, 'toString', {
          value: patched, enumerable: false, configurable: true, writable: true
        });
        Object.defineProperty(patched, 'toString', {
          value: function() { return 'function toString() { [native code] }'; },
          enumerable: false, configurable: true
        });
      } catch(e) {}
    })();

    // ── 26. Eval native string ────────────────────────────────────────────
    try {
      window.eval.toString = function() { return 'function eval() { [native code] }'; };
    } catch(e) {}

    // ── 27. Hide _wk JS channel from property enumeration ────────────────
    // ── 27. Fix _wk + hide webkit.messageHandlers (WKWebView fingerprint) ──
    // webkit.messageHandlers が存在すると WKWebView と即バレ。
    // Flutter proxy (window._wk) が webkit.messageHandlers チェーンを使うので
    // まずネイティブハンドラへの直接参照を保存してから隠す。
    try {
      var _mh = window.webkit && window.webkit.messageHandlers;
      if (_mh && _mh._wk) {
        var _nh = _mh._wk;
        Object.defineProperty(window, '_wk', {
          value: _nh, enumerable: false, configurable: true, writable: false
        });
        try {
          Object.defineProperty(window.webkit, 'messageHandlers', {
            value: undefined, enumerable: false, configurable: true
          });
        } catch(e) {
          try {
            Object.defineProperty(window, 'webkit', {
              value: Object.create(null), enumerable: false, configurable: true, writable: true
            });
          } catch(e2) {}
        }
      } else if (window._wk) {
        Object.defineProperty(window, '_wk', {
          value: window._wk, enumerable: false, configurable: true, writable: false
        });
      }
    } catch(e) {}

    // ── 28. window.safari (Safari.app has it; WKWebView does not) ─────────
    try {
      if (!window.safari) {
        Object.defineProperty(window, 'safari', {
          value: {pushNotification:{
            permission: function() { return {permission:'default'}; },
            requestPermission: function() {}
          }},
          enumerable: false, configurable: true
        });
      }
    } catch(e) {}

    // ── 29. navigator.webdriver = false ───────────────────────────────────
    try {
      Object.defineProperty(navigator, 'webdriver', {
        get: function() { return false; },
        enumerable: true, configurable: true
      });
    } catch(e) {}

    // ── 30. navigator.permissions.query — WKWebView may return 'denied'
    //        for permissions Safari returns 'prompt'; patch to 'prompt'. ──
    try {
      if (navigator.permissions && navigator.permissions.query) {
        var _origQuery = navigator.permissions.query.bind(navigator.permissions);
        navigator.permissions.query = function(params) {
          var name = params && params.name;
          if (name === 'geolocation' || name === 'camera' || name === 'microphone' ||
              name === 'notifications' || name === 'push') {
            return Promise.resolve({ state: 'prompt', onchange: null });
          }
          return _origQuery(params);
        };
      }
    } catch(e) {}

    // ── 31. Notification.permission — iOS Safari: 'default' ───────────────
    try {
      if (typeof Notification !== 'undefined') {
        Object.defineProperty(Notification, 'permission', {
          get: function() { return 'default'; },
          configurable: true
        });
      }
    } catch(e) {}

    // ── 32. Hardware APIs Safari iOS does NOT have ───────────────────────
    try {
      var hwApis = ['bluetooth', 'usb', 'hid', 'serial'];
      for (var hi = 0; hi < hwApis.length; hi++) {
        try {
          Object.defineProperty(navigator, hwApis[hi], {
            get: function() { return undefined; },
            configurable: true
          });
        } catch(e) {}
      }
    } catch(e) {}

    // ── 33. navigator basics ─────────────────────────────────────────────
    try {
      Object.defineProperty(nav, 'cookieEnabled', { get: function() { return true; }, configurable: true });
    } catch(e) {}
    try {
      Object.defineProperty(nav, 'doNotTrack', { get: function() { return null; }, configurable: true });
    } catch(e) {}
    try {
      nav.javaEnabled = function() { return false; };
      nativeStr(nav.javaEnabled, 'javaEnabled');
    } catch(e) {}

    // ── 34. OfflineAudioContext noise (parallel với AudioContext) ────────
    try {
      var Off = window.OfflineAudioContext || window.webkitOfflineAudioContext;
      if (Off) {
        var origGetChannelData = AudioBuffer.prototype.getChannelData;
        AudioBuffer.prototype.getChannelData = function() {
          var data = origGetChannelData.apply(this, arguments);
          // Apply same noise pattern (per-arguments, deterministic per-session)
          var noise = (window._fpAudioNoise = window._fpAudioNoise || (Math.random() * 0.0000001));
          for (var i = 0; i < data.length; i += 100) {
            data[i] = data[i] + noise;
          }
          return data;
        };
        nativeStr(AudioBuffer.prototype.getChannelData, 'getChannelData');
      }
    } catch(e) {}

    // ── 35. Date timezone offset stability (JST = -540) ──────────────────
    try {
      var origTZ = Date.prototype.getTimezoneOffset;
      Date.prototype.getTimezoneOffset = function() { return -540; };
      nativeStr(Date.prototype.getTimezoneOffset, 'getTimezoneOffset');
    } catch(e) {}

    // ── 36. screen.availLeft / availTop — iOS Safari: 0 ──────────────────
    try {
      Object.defineProperty(screen, 'availLeft', { get: function() { return 0; }, configurable: true });
      Object.defineProperty(screen, 'availTop', { get: function() { return 0; }, configurable: true });
    } catch(e) {}

    // ── 37. PointerEvent existence — iOS Safari has it ───────────────────
    try {
      if (typeof window.PointerEvent === 'undefined') {
        window.PointerEvent = function() {};
      }
    } catch(e) {}

  } catch(e) {}
})();
''';
}

String _jsEsc(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll("'", "\\'")
    .replaceAll('\n', '\\n')
    .replaceAll('\r', '\\r');

String buildAutoFillScript(String email, String password,
    {int minDelay = 80, int maxDelay = 180}) {
  final safeEmail = _jsEsc(email);
  final safePass = _jsEsc(password);
  return '''
(function() {
  var minD = $minDelay, maxD = $maxDelay;
  var nSet = (Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value') || {}).set;

  function setVal(el, v) {
    if (nSet) nSet.call(el, v); else el.value = v;
  }

  function typeChars(el, text, onDone) {
    el.focus();
    setVal(el, '');
    el.dispatchEvent(new Event('input', {bubbles:true}));
    var i = 0;
    function next() {
      if (i >= text.length) {
        el.dispatchEvent(new Event('change', {bubbles:true}));
        el.dispatchEvent(new Event('blur', {bubbles:true}));
        onDone();
        return;
      }
      var ch = text[i++];
      el.dispatchEvent(new KeyboardEvent('keydown',  {key:ch, bubbles:true, cancelable:true}));
      el.dispatchEvent(new KeyboardEvent('keypress', {key:ch, charCode:ch.charCodeAt(0), bubbles:true, cancelable:true}));
      setVal(el, el.value + ch);
      el.dispatchEvent(new Event('input', {bubbles:true}));
      el.dispatchEvent(new KeyboardEvent('keyup', {key:ch, bubbles:true}));
      setTimeout(next, minD + Math.random() * (maxD - minD));
    }
    setTimeout(next, minD + Math.random() * (maxD - minD));
  }

  function findFirst(sels) {
    for (var i = 0; i < sels.length; i++) {
      var el = document.querySelector(sels[i]);
      if (el) return el;
    }
    return null;
  }

  var emailEl = findFirst(['input[type="email"]','input[name="email"]','input[name="loginEmail"]','input[name="username"]','input[id*="email"]','input[placeholder*="メール"]','input[placeholder*="email" i]']);
  var passEl  = findFirst(['input[type="password"]','input[name="password"]','input[name="loginPassword"]','input[id*="pass"]']);

  // Pause ~1.5-2.5s + nhẹ scroll viewport trước khi login (không dùng TouchEvent —
  // JS-dispatched events có isTrusted:false bị reCAPTCHA phát hiện ngay)
  function pauseThenDone(onDone) {
    var steps = 6 + Math.floor(Math.random() * 5);
    var dir   = Math.random() > 0.5 ? -1 : 1;
    var dist  = 40 + Math.floor(Math.random() * 60);
    var total = 1500 + Math.floor(Math.random() * 1000);
    var delay = Math.floor(total / steps);
    var step  = 0;
    function tick() {
      if (step >= steps) { onDone(); return; }
      window.scrollBy(0, dir * Math.round(dist / steps));
      step++;
      setTimeout(tick, delay + Math.floor(Math.random() * 30) - 15);
    }
    setTimeout(tick, 80 + Math.floor(Math.random() * 120));
  }

  function afterType() {
    pauseThenDone(function() {
      window._wk.postMessage('{"type":"typeDone","field":"autofill"}');
    });
  }

  if (emailEl && passEl) {
    typeChars(emailEl, '$safeEmail', function() { typeChars(passEl, '$safePass', afterType); });
  } else if (emailEl) {
    typeChars(emailEl, '$safeEmail', afterType);
  } else if (passEl) {
    typeChars(passEl, '$safePass', afterType);
  } else {
    window._wk.postMessage('{"type":"typeDone","field":"autofill"}');
  }
})();
''';
}

String buildOtpAutoSubmitScript(String otp,
    {int minDelay = 80, int maxDelay = 180}) {
  return '''
(function() {
  var minD = $minDelay, maxD = $maxDelay;
  var nSet = (Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value') || {}).set;

  function setVal(el, v) {
    if (nSet) nSet.call(el, v); else el.value = v;
  }

  function typeChars(el, text, onDone) {
    el.focus();
    setVal(el, '');
    el.dispatchEvent(new Event('input', {bubbles:true}));
    var i = 0;
    function next() {
      if (i >= text.length) {
        el.dispatchEvent(new Event('change', {bubbles:true}));
        el.dispatchEvent(new KeyboardEvent('keyup', {bubbles:true}));
        onDone();
        return;
      }
      var ch = text[i++];
      el.dispatchEvent(new KeyboardEvent('keydown',  {key:ch, bubbles:true, cancelable:true}));
      el.dispatchEvent(new KeyboardEvent('keypress', {key:ch, charCode:ch.charCodeAt(0), bubbles:true, cancelable:true}));
      setVal(el, el.value + ch);
      el.dispatchEvent(new Event('input', {bubbles:true}));
      el.dispatchEvent(new KeyboardEvent('keyup', {key:ch, bubbles:true}));
      setTimeout(next, minD + Math.random() * (maxD - minD));
    }
    setTimeout(next, minD + Math.random() * (maxD - minD));
  }

  function findFirst(sels) {
    for (var i = 0; i < sels.length; i++) {
      var el = document.querySelector(sels[i]);
      if (el) return el;
    }
    return null;
  }

  var el = findFirst([
    'input#authCode','input[name="dwfrm_factor2Auth_authCode"]',
    'input[name="passcode"]','input[name="otp"]','input[name="code"]',
    'input[id*="auth"]','input[id*="otp"]','input[id*="passcode"]',
    'input[placeholder*="パスコード"]','input[maxlength="6"]',
  ]);

  if (!el) {
    window._wk.postMessage('{"type":"otpStatus","status":"noField"}');
    return;
  }

  window._wk.postMessage('{"type":"otpStatus","status":"filling"}');

  typeChars(el, '$otp', function() {
    window._wk.postMessage('{"type":"otpStatus","status":"filled"}');
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
        window._wk.postMessage('{"type":"otpStatus","status":"submitted"}');
      } else {
        window._wk.postMessage('{"type":"otpStatus","status":"noButton"}');
      }
    }, 600);
  });
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
    window._wk.postMessage(JSON.stringify({type:'otpError',detected:true}));
  }
})();
''';
}
