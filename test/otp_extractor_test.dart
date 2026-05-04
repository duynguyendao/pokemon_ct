import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_ct/services/otp_extractor.dart';

void main() {
  test('extracts Pokemon Center Japanese passcode', () {
    expect(extractOtpFromText('【パスコード】 568661'), '568661');
  });

  test('extracts Japanese verification code variants', () {
    expect(extractOtpFromText('認証コード：123456'), '123456');
    expect(extractOtpFromText('確認コード 654321'), '654321');
  });

  test('normalizes full-width digits', () {
    expect(extractOtpFromText('コード：１２３４５６'), '123456');
  });

  test('extracts English code variants', () {
    expect(extractOtpFromText('Your verification code is 778899'), '778899');
  });
}
