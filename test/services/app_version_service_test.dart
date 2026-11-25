import 'package:flutter_test/flutter_test.dart';
import 'package:fieldlog_mobile/services/app_version_service.dart';

void main() {
  group('compareVersions', () {
    test('orders versions numerically', () {
      expect(AppVersionService.compareVersions('1.0.3', '1.1.0'), -1);
      expect(AppVersionService.compareVersions('1.10.0', '1.9.0'), 1);
      expect(AppVersionService.compareVersions('2.0.0', '1.99.99'), 1);
    });

    test('treats missing parts as zero and ignores build metadata', () {
      expect(AppVersionService.compareVersions('1.1', '1.1.0'), 0);
      expect(AppVersionService.compareVersions('1.1.0+5', '1.1.0'), 0);
    });
  });

  group('isUnsupportedResponse', () {
    test('accepts 426 with the unsupported code', () {
      expect(
        AppVersionService.isUnsupportedResponse(
          426,
          '{"code":"app_version_unsupported","min_version":"1.1.0"}',
        ),
        isTrue,
      );
    });

    test('rejects other statuses, codes and bodies', () {
      expect(
        AppVersionService.isUnsupportedResponse(
            400, '{"code":"app_version_unsupported"}'),
        isFalse,
      );
      expect(
        AppVersionService.isUnsupportedResponse(426, '{"code":"other"}'),
        isFalse,
      );
      expect(AppVersionService.isUnsupportedResponse(426, 'not json'), isFalse);
    });
  });

  group('handleResponse', () {
    tearDown(() {
      AppVersionService.updateRequired.value = false;
      AppVersionService.updateUrl = AppVersionService.defaultUpdateUrl;
    });

    test('flags update required and stores the server update url', () {
      final handled = AppVersionService.handleResponse(
        426,
        '{"code":"app_version_unsupported","update_url":"https://example.org/u"}',
      );
      expect(handled, isTrue);
      expect(AppVersionService.updateRequired.value, isTrue);
      expect(AppVersionService.updateUrl, 'https://example.org/u');
    });

    test('keeps default url when server sends none', () {
      AppVersionService.handleResponse(
        426,
        '{"code":"app_version_unsupported","update_url":""}',
      );
      expect(AppVersionService.updateUrl, AppVersionService.defaultUpdateUrl);
    });

    test('ignores ordinary errors', () {
      expect(AppVersionService.handleResponse(400, '{}'), isFalse);
      expect(AppVersionService.updateRequired.value, isFalse);
    });
  });

  test('headers are empty until version is known', () {
    expect(AppVersionService.headers, isEmpty);
  });
}
