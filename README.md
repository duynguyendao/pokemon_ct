# PokemonCT - Account Manager for iOS

Fast account management tool cho Pokemon Center với anti-fingerprint browser, OTP monitor, và proxy management.

## 🚀 Chạy App

### Yêu cầu
- macOS + Xcode (để build cho iPhone)
- Flutter SDK 3.11+
- iOS 12.0+

### Build & Run
```bash
cd pokemon_ct
flutter pub get
flutter run -d <device-id>
```

## 🔧 Cấu hình IMAP (OTP Monitor)

### Gmail (khuyên dùng)
1. **Bật 2-Factor**: myaccount.google.com → Security
2. **App Password**: 
   - Security → App passwords
   - Chọn Mail & iOS
   - Copy password (có spaces)
   - Dán vào app, **KHÔNG cần xóa spaces**

3. **Cài trong app**:
   - Host: `imap.gmail.com`
   - Port: `993`
   - Email: `your@gmail.com`
   - Password: `abcd efgh ijkl mnop` (paste nguyên)

## 📋 Hướng dẫn

**Tab 1 - Tài Khoản**: Import batch, search, filter
**Tab 2 - OTP**: Setup IMAP, monitor OTP tự động
**Tab 3 - Proxy**: Add, enable/disable, copy

**Browser**: Anti-fingerprint JS, auto-fill, auto OTP

## 🎯 Features
✅ Batch import | Anti-fingerprint | IMAP OTP | Proxy manager | Dark theme | Groups | Swipe-to-delete

## 📝 Notes
- Data lưu local
- iOS 12.0+ support
- No ads, no tracking

Made with Flutter 💙
