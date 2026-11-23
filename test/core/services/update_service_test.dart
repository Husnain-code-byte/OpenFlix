import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/core/services/update_service.dart';

void main() {
  group('UpdateService', () {
    test('compares semantic versions strictly (major.minor.patch)', () {
      expect(UpdateService.isNewerVersion('v1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('v1.1.0', '1.0.9'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewerVersion('v1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v0.9.9', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.1+2', '1.0.0+9'), isTrue);
    });

    test('selectBestApkAsset matches ABI, falls back to universal, and rejects releases without APKs', () {
      expect(
        UpdateService.selectBestApkAsset(const [
          {'name': 'source.zip', 'browser_download_url': 'https://example.com/source.zip'},
        ]),
        isNull,
      );

      final arm64 = UpdateService.selectBestApkAsset(
        const [
          {
            'name': 'OpenFlix-universal-v1.0.1.apk',
            'browser_download_url': 'https://example.com/universal.apk',
            'size': 110000000,
          },
          {
            'name': 'OpenFlix-arm64-v8a-v1.0.1.apk',
            'browser_download_url': 'https://example.com/arm64.apk',
            'size': 78000000,
          },
        ],
        preferredAbiTokensOverride: const ['arm64-v8a', 'arm64'],
      );
      expect(arm64?.url, 'https://example.com/arm64.apk');
      expect(arm64?.sizeBytes, 78000000);

      final universalFallback = UpdateService.selectBestApkAsset(
        const [
          {
            'name': 'OpenFlix-universal-v1.0.1.apk',
            'browser_download_url': 'https://example.com/universal.apk',
            'size': 110000000,
          },
          {
            'name': 'OpenFlix-x86_64-v1.0.1.apk',
            'browser_download_url': 'https://example.com/x86_64.apk',
            'size': 80000000,
          },
        ],
        preferredAbiTokensOverride: const ['armeabi-v7a'],
      );
      expect(universalFallback?.url, 'https://example.com/universal.apk');
    });

    test('parseReleaseNotes strips markdown noise into clean heading and bullet entries', () {
      const raw = '''
## What's Fixed
- **Playback**: Fixed `hwdec` freeze on MediaTek devices
* Added [Skip Outro](https://example.com) timing support

---
**Full Changelog**: https://github.com/Husnain-code-byte/OpenFlix/compare/v1.0.0...v1.0.1
''';
      final parsed = UpdateService.parseReleaseNotes(raw);
      expect(parsed.length, 3);
      expect(parsed[0].isHeading, isTrue);
      expect(parsed[0].text, "What's Fixed");
      expect(parsed[1].isHeading, isFalse);
      expect(parsed[1].text, 'Playback: Fixed hwdec freeze on MediaTek devices');
      expect(parsed[2].text, 'Added Skip Outro timing support');
    });

    test('deduplicates dismissal per session', () {
      final svc = UpdateService();
      expect(svc.isDismissedInSession('v1.0.2'), isFalse);
      svc.dismissForCurrentSession('v1.0.2');
      expect(svc.isDismissedInSession('1.0.2'), isTrue);
      expect(svc.isDismissedInSession('v1.0.3'), isFalse);
    });
  });
}
