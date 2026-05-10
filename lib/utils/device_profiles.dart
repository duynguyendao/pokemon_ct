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

// Chỉ dùng Safari iOS profiles vì WKWebView KHÔNG thể giả lập
// Sec-CH-UA / Sec-CH-UA-Mobile / Sec-CH-UA-Platform headers (Chrome/Android cần
// các header này → server detect bot ngay nếu UA là Chrome nhưng thiếu headers).
const List<DeviceProfile> kDeviceProfiles = [
  DeviceProfile(
    name: 'iPhone 16 Pro Max',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 6,
    deviceMemory: 8,
    screenWidth: 440,
    screenHeight: 956,
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
    name: 'iPhone 16',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1',
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
    name: 'iPhone 15 Pro Max',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 6,
    deviceMemory: 8,
    screenWidth: 430,
    screenHeight: 932,
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
    name: 'iPhone 15 Plus',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 6,
    deviceMemory: 6,
    screenWidth: 430,
    screenHeight: 932,
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
    name: 'iPhone 14 Pro Max',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_6_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6.1 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'ja', 'en-US'],
    hardwareConcurrency: 6,
    deviceMemory: 6,
    screenWidth: 430,
    screenHeight: 932,
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
    name: 'iPhone 13 Pro',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1',
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
];

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

  // Safari/iOS profile vs Chrome/Android profile — nhiều thứ khác nhau hoàn toàn
  final isSafari = p.userAgent.contains('Safari') && !p.userAgent.contains('Chrome');
  // appVersion = phần sau "Mozilla/" trong UA
  final appVersion = p.userAgent.startsWith('Mozilla/')
      ? p.userAgent.substring('Mozilla/'.length)
      : '5.0 (Mobile)';

  // Chrome profiles: plugins có PDF Viewer; Safari iOS: PluginArray rỗng
  final pluginsJs = isSafari
      ? 'def(nav, "plugins", Object.freeze([]));'
      : '''def(nav, 'plugins', Object.freeze([
      { name: 'PDF Viewer', filename: 'internal-pdf-viewer', description: 'Portable Document Format', suffixes: 'pdf' },
      { name: 'Chrome PDF Viewer', filename: 'internal-pdf-viewer', description: 'Portable Document Format', suffixes: 'pdf' },
      { name: 'Chromium PDF Viewer', filename: 'internal-pdf-viewer', description: 'Portable Document Format', suffixes: 'pdf' },
    ]));''';

  // Safari không có window.chrome; Chrome cần nó
  final chromeJs = isSafari
      ? '''try { delete window.chrome; } catch(e) {}
    Object.defineProperty(window, 'chrome', { get: () => undefined, configurable: true, enumerable: false });'''
      : '''window.chrome = {
      app: { isInstalled: false, runningState: 'cannot_run', getDetails: function(){ return null; }, getIsInstalled: function(){ return false; } },
      runtime: {
        id: undefined,
        connect: function(){ return { onMessage: { addListener: function(){} }, onDisconnect: { addListener: function(){} }, postMessage: function(){} }; },
        sendMessage: function(){},
        onConnect: { addListener: function(){} },
        onMessage: { addListener: function(){} },
        getPlatformInfo: function(cb) {
          var info = { os: 'android', arch: 'arm', nacl_arch: 'arm' };
          if (cb) cb(info);
          return Promise.resolve(info);
        },
      },
      loadTimes: function(){ return { firstPaintTime: 0, firstPaintAfterLoadTime: 0, requestTime: Date.now() / 1000, startLoadTime: Date.now() / 1000 }; },
      csi: function(){ return { startE: Date.now(), onloadT: Date.now(), pageT: 1.0, tran: 15 }; },
    };''';

  // Safari iOS có navigator.standalone; Chrome không có
  final standaloneJs = isSafari
      ? 'def(nav, "standalone", false);'
      : '';

  // Chrome/Android — extract version + model for userAgentData
  final chromeMatch = RegExp(r'Chrome/(\d+)').firstMatch(p.userAgent);
  final chromeVersion = chromeMatch?.group(1) ?? '136';
  final androidVerMatch = RegExp(r'Android (\d+)').firstMatch(p.userAgent);
  final androidVersion = androidVerMatch?.group(1) ?? '15';
  final parenMatch = RegExp(r'\(([^)]+)\)').firstMatch(p.userAgent);
  final parenParts = (parenMatch?.group(1) ?? '').split(';');
  final androidModel = isSafari
      ? ''
      : (parenParts.length >= 3 ? parenParts[2].trim() : '');

  return '''
(function() {
  if (window.__fpPatched) return;
  window.__fpPatched = true;

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

    // ── 1. navigator ───────────────────────────────────────────────────────
    def(nav, 'platform',            '${p.platform}');
    def(nav, 'vendor',              '${p.vendor}');
    def(nav, 'userAgent',           '${p.userAgent}');
    def(nav, 'appVersion',          '$appVersion');
    def(nav, 'appName',             'Netscape');
    def(nav, 'product',             'Gecko');
    def(nav, 'hardwareConcurrency', ${p.hardwareConcurrency});
    def(nav, 'deviceMemory',        ${p.deviceMemory});
    def(nav, 'language',            '${p.languages.first}');
    def(nav, 'languages',           Object.freeze([$langs]));
    def(nav, 'maxTouchPoints',      ${p.maxTouchPoints});
    def(nav, 'doNotTrack',          null);
    def(nav, 'cookieEnabled',       true);
    def(nav, 'onLine',              true);
    // CRITICAL: webdriver must be undefined (non-existent), not false — real browsers don't define this
    try { delete nav.__proto__.webdriver; } catch(e) {}
    try { Object.defineProperty(nav, 'webdriver', { get: () => undefined, configurable: true, enumerable: false }); } catch(e) {}
    $standaloneJs

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

    // ── 4. Canvas noise ────────────────────────────────────────────────────
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
          img.data[i]     = (img.data[i]     + (s & 3))        & 0xFF;
          img.data[i + 1] = (img.data[i + 1] + ((s >> 2) & 3)) & 0xFF;
          img.data[i + 2] = (img.data[i + 2] + ((s >> 4) & 3)) & 0xFF;
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

    // ── 5. AudioContext ────────────────────────────────────────────────────
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
    })();

    // ── 7. Network & battery ───────────────────────────────────────────────
    if (nav.connection) {
      def(nav, 'connection', {
        effectiveType: '4g',
        downlink: 8 + (SEED % 5),
        rtt: 40 + (SEED % 30),
        saveData: false,
        type: 'wifi',
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
    }

    // ── 9. chrome object — Safari không có, Chrome cần có ─────────────────
    try { delete window.cdc_adoQpoasnfa76pfcZLmcfl_Array; } catch(e) {}
    try { delete window.cdc_adoQpoasnfa76pfcZLmcfl_Promise; } catch(e) {}
    try { delete window.cdc_adoQpoasnfa76pfcZLmcfl_Symbol; } catch(e) {}
    $chromeJs

    // ── 10. Plugins — Safari iOS: rỗng; Chrome: PDF Viewer ────────────────
    $pluginsJs

    // ── 11. matchMedia — color gamut + mobile pointer/hover consistency ───────
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
          }
        } catch(e) {}
        return result;
      };
    })();

    // ── 12. UA Client Hints (userAgentData) — Chrome/Android only ─────────
    (function patchUAClientHints() {
      if (!nav.userAgent.includes('Chrome')) return;
      const brands = [
        { brand: 'Not/A)Brand',   version: '8' },
        { brand: 'Chromium',      version: '$chromeVersion' },
        { brand: 'Google Chrome', version: '$chromeVersion' },
      ];
      const hi = {
        brands: brands, mobile: true, platform: 'Android',
        platformVersion: '$androidVersion', architecture: 'arm', bitness: '64',
        model: '$androidModel', uaFullVersion: '$chromeVersion.0.0.0',
        fullVersionList: brands.map(function(b){ return {brand:b.brand, version:'$chromeVersion.0.0.0'}; }),
      };
      def(nav, 'userAgentData', {
        brands: brands, mobile: true, platform: 'Android',
        toJSON: function(){ return {brands:brands, mobile:true, platform:'Android'}; },
        getHighEntropyValues: function(){ return Promise.resolve(hi); },
      });
    })();

    // ── 13. Block RTCPeerConnection JS-level (IP leak) ─────────────────────
    try { Object.defineProperty(window,'RTCPeerConnection',       {value:undefined,configurable:true}); } catch(e) {}
    try { Object.defineProperty(window,'webkitRTCPeerConnection', {value:undefined,configurable:true}); } catch(e) {}

    // ── 14. performance.memory ─────────────────────────────────────────────
    (function(){
      if (!window.performance) return;
      try {
        Object.defineProperty(window.performance,'memory',{
          get:function(){ return {
            usedJSHeapSize:  18000000 + ((SEED*7)%8000000),
            totalJSHeapSize: 40000000 + ((SEED*3)%12000000),
            jsHeapSizeLimit: 2197815296,
          };}, configurable:true
        });
      } catch(e) {}
    })();

    // ── 15. document.visibilityState — always visible ──────────────────────
    try { Object.defineProperty(document,'visibilityState',{get:()=>'visible',configurable:true}); } catch(e) {}
    try { Object.defineProperty(document,'hidden',         {get:()=>false,    configurable:true}); } catch(e) {}

    // ── 16. pdfViewerEnabled (Chrome: true, Safari: false) ────────────────
    def(nav, 'pdfViewerEnabled', ${!isSafari});

    // ── 17. screen.orientation ────────────────────────────────────────────
    try {
      Object.defineProperty(screen,'orientation',{
        get:()=>({type:'portrait-primary',angle:0,onchange:null}), configurable:true
      });
    } catch(e) {}

    // ── 18. navigator.mimeTypes — consistent with plugins ────────────────────
    (function patchMimeTypes() {
      if (!nav.userAgent.includes('Chrome')) return;
      try {
        const pdf = { type: 'application/pdf', suffixes: 'pdf', description: 'Portable Document Format', enabledPlugin: (nav.plugins && nav.plugins[0]) || {} };
        const pdf2 = { type: 'text/pdf', suffixes: 'pdf', description: 'Portable Document Format', enabledPlugin: (nav.plugins && nav.plugins[0]) || {} };
        def(nav, 'mimeTypes', Object.freeze([pdf, pdf2]));
      } catch(e) {}
    })();

    // ── 19. Hide automation eval strings ─────────────────────────────────────
    (function patchEval() {
      const origEval = window.eval;
      window.eval = function(code) {
        return origEval.call(this, code);
      };
      window.eval.toString = function() { return 'function eval() { [native code] }'; };
      Function.prototype.toString = (function(origToString) {
        return function() {
          const s = origToString.call(this);
          if (s.includes('__puppeteer') || s.includes('__playwright') || s.includes('__webdriver')) {
            return 'function () { [native code] }';
          }
          return s;
        };
      })(Function.prototype.toString);
    })();

    // ── 20. navigator.connection — mobile LTE/5G ──────────────────────────────
    (function patchConnection() {
      const conn = {
        effectiveType: '4g',
        downlink: 8 + (SEED % 5),
        downlinkMax: Infinity,
        rtt: 40 + (SEED % 30),
        saveData: false,
        type: 'cellular',
        onchange: null,
        ontypechange: null,
      };
      try { def(nav, 'connection', conn); } catch(e) {}
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
