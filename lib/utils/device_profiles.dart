class DeviceProfile {
  final String name;
  final String userAgent;
  final String platform;
  final String vendor;
  final List<String> languages;
  final int hardwareConcurrency;
  final int screenWidth;
  final int screenHeight;
  final double devicePixelRatio;
  final int maxTouchPoints;
  final String webglVendor;
  final String webglRenderer;

  const DeviceProfile({
    required this.name,
    required this.userAgent,
    required this.platform,
    required this.vendor,
    required this.languages,
    required this.hardwareConcurrency,
    required this.screenWidth,
    required this.screenHeight,
    required this.devicePixelRatio,
    required this.maxTouchPoints,
    required this.webglVendor,
    required this.webglRenderer,
  });
}

const List<DeviceProfile> kDeviceProfiles = [
  DeviceProfile(
    name: 'iPhone 15 Pro',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'en-US'],
    hardwareConcurrency: 6,
    screenWidth: 393,
    screenHeight: 852,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Apple Inc.',
    webglRenderer: 'Apple GPU',
  ),
  DeviceProfile(
    name: 'iPhone 14',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'en-US'],
    hardwareConcurrency: 6,
    screenWidth: 390,
    screenHeight: 844,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Apple Inc.',
    webglRenderer: 'Apple GPU',
  ),
  DeviceProfile(
    name: 'iPhone 13',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 15_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6.1 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'en-US'],
    hardwareConcurrency: 6,
    screenWidth: 390,
    screenHeight: 844,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Apple Inc.',
    webglRenderer: 'Apple GPU',
  ),
  DeviceProfile(
    name: 'iPhone SE 3rd Gen',
    userAgent:
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1',
    platform: 'iPhone',
    vendor: 'Apple Computer, Inc.',
    languages: ['ja-JP', 'en-US'],
    hardwareConcurrency: 6,
    screenWidth: 375,
    screenHeight: 667,
    devicePixelRatio: 2.0,
    maxTouchPoints: 5,
    webglVendor: 'Apple Inc.',
    webglRenderer: 'Apple GPU',
  ),
  DeviceProfile(
    name: 'Samsung Galaxy S23',
    userAgent:
        'Mozilla/5.0 (Linux; Android 13; SM-S911B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36',
    platform: 'Linux armv81',
    vendor: 'Google Inc.',
    languages: ['ja-JP', 'en-US'],
    hardwareConcurrency: 8,
    screenWidth: 393,
    screenHeight: 851,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Qualcomm',
    webglRenderer: 'Adreno (TM) 740',
  ),
  DeviceProfile(
    name: 'Samsung Galaxy S22',
    userAgent:
        'Mozilla/5.0 (Linux; Android 12; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Mobile Safari/537.36',
    platform: 'Linux armv81',
    vendor: 'Google Inc.',
    languages: ['ja-JP', 'en-US'],
    hardwareConcurrency: 8,
    screenWidth: 360,
    screenHeight: 780,
    devicePixelRatio: 3.0,
    maxTouchPoints: 5,
    webglVendor: 'Qualcomm',
    webglRenderer: 'Adreno (TM) 730',
  ),
  DeviceProfile(
    name: 'Google Pixel 8',
    userAgent:
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    platform: 'Linux armv81',
    vendor: 'Google Inc.',
    languages: ['ja-JP', 'en-US'],
    hardwareConcurrency: 8,
    screenWidth: 412,
    screenHeight: 892,
    devicePixelRatio: 2.625,
    maxTouchPoints: 5,
    webglVendor: 'ARM',
    webglRenderer: 'Mali-G715',
  ),
  DeviceProfile(
    name: 'Google Pixel 7',
    userAgent:
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36',
    platform: 'Linux armv81',
    vendor: 'Google Inc.',
    languages: ['ja-JP', 'en-US'],
    hardwareConcurrency: 8,
    screenWidth: 412,
    screenHeight: 892,
    devicePixelRatio: 2.625,
    maxTouchPoints: 5,
    webglVendor: 'ARM',
    webglRenderer: 'Mali-G710',
  ),
  DeviceProfile(
    name: 'Xiaomi 13',
    userAgent:
        'Mozilla/5.0 (Linux; Android 13; 2211133C) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36',
    platform: 'Linux armv81',
    vendor: 'Google Inc.',
    languages: ['ja-JP', 'en-US'],
    hardwareConcurrency: 8,
    screenWidth: 393,
    screenHeight: 851,
    devicePixelRatio: 2.75,
    maxTouchPoints: 5,
    webglVendor: 'Qualcomm',
    webglRenderer: 'Adreno (TM) 740',
  ),
  DeviceProfile(
    name: 'OnePlus 11',
    userAgent:
        'Mozilla/5.0 (Linux; Android 13; CPH2449) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Mobile Safari/537.36',
    platform: 'Linux armv81',
    vendor: 'Google Inc.',
    languages: ['ja-JP', 'en-US'],
    hardwareConcurrency: 8,
    screenWidth: 412,
    screenHeight: 919,
    devicePixelRatio: 2.625,
    maxTouchPoints: 5,
    webglVendor: 'Qualcomm',
    webglRenderer: 'Adreno (TM) 740',
  ),
];

DeviceProfile randomProfile() {
  final index = DateTime.now().millisecondsSinceEpoch % kDeviceProfiles.length;
  return kDeviceProfiles[index];
}

String buildAntiFingerprintScript(DeviceProfile profile) {
  final langs = profile.languages.map((l) => '"$l"').join(', ');
  return '''
(function() {
  try {
    Object.defineProperty(navigator, 'platform', { get: () => '${profile.platform}' });
    Object.defineProperty(navigator, 'vendor', { get: () => '${profile.vendor}' });
    Object.defineProperty(navigator, 'userAgent', { get: () => '${profile.userAgent}' });
    Object.defineProperty(navigator, 'appVersion', { get: () => '5.0 (Mobile)' });
    Object.defineProperty(navigator, 'hardwareConcurrency', { get: () => ${profile.hardwareConcurrency} });
    Object.defineProperty(navigator, 'languages', { get: () => [$langs] });
    Object.defineProperty(navigator, 'language', { get: () => '${profile.languages.first}' });
    Object.defineProperty(navigator, 'maxTouchPoints', { get: () => ${profile.maxTouchPoints} });
    Object.defineProperty(navigator, 'deviceMemory', { get: () => 4 });
    Object.defineProperty(screen, 'width', { get: () => ${profile.screenWidth} });
    Object.defineProperty(screen, 'height', { get: () => ${profile.screenHeight} });
    Object.defineProperty(screen, 'availWidth', { get: () => ${profile.screenWidth} });
    Object.defineProperty(screen, 'availHeight', { get: () => ${profile.screenHeight - 40} });
    Object.defineProperty(screen, 'colorDepth', { get: () => 24 });
    Object.defineProperty(screen, 'pixelDepth', { get: () => 24 });
    Object.defineProperty(window, 'devicePixelRatio', { get: () => ${profile.devicePixelRatio} });

    const origGetParameter = WebGLRenderingContext.prototype.getParameter;
    WebGLRenderingContext.prototype.getParameter = function(param) {
      if (param === 0x9245) return '${profile.webglVendor}';
      if (param === 0x9246) return '${profile.webglRenderer}';
      return origGetParameter.call(this, param);
    };

    Object.defineProperty(navigator, 'connection', {
      get: () => ({ effectiveType: '4g', type: 'wifi', downlink: 10, rtt: 50 })
    });

    navigator.getBattery = () => Promise.resolve({
      charging: true, chargingTime: 0, dischargingTime: Infinity, level: 0.9
    });

    const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = function(type) {
      const ctx = this.getContext('2d');
      if (ctx) {
        const imageData = ctx.getImageData(0, 0, this.width, this.height);
        for (let i = 0; i < 10; i++) {
          imageData.data[i * 4] ^= 1;
        }
        ctx.putImageData(imageData, 0, 0);
      }
      return origToDataURL.apply(this, arguments);
    };
  } catch(e) {}
})();
''';
}

String buildAutoFillScript(String email, String password) {
  return '''
(function() {
  function fillField(selector, value) {
    const el = document.querySelector(selector);
    if (el) {
      el.value = value;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    }
    return false;
  }

  const emailSelectors = [
    'input[type="email"]',
    'input[name="email"]',
    'input[name="username"]',
    'input[id*="email"]',
    'input[placeholder*="メール"]',
    'input[placeholder*="email"]',
  ];

  const passSelectors = [
    'input[type="password"]',
    'input[name="password"]',
    'input[id*="pass"]',
  ];

  for (const sel of emailSelectors) {
    if (fillField(sel, '${email.replaceAll("'", "\\'")}')) break;
  }

  for (const sel of passSelectors) {
    if (fillField(sel, '${password.replaceAll("'", "\\'")}')) break;
  }
})();
''';
}

String buildOtpFillScript(String otp) {
  return '''
(function() {
  function fill(selector, val) {
    const el = document.querySelector(selector);
    if (el) {
      el.value = val;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    }
    return false;
  }

  const otpSelectors = [
    'input[name="otp"]',
    'input[name="code"]',
    'input[name="token"]',
    'input[id*="otp"]',
    'input[id*="code"]',
    'input[placeholder*="認証"]',
    'input[placeholder*="コード"]',
    'input[maxlength="6"]',
    'input[maxlength="4"]',
  ];

  for (const sel of otpSelectors) {
    if (fill(sel, '$otp')) break;
  }
})();
''';
}
