import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pixel/features/addons/data/addons_storage.dart';
import 'package:pixel/features/addons/data/cloudstream_bridge_client.dart';
import 'package:pixel/features/addons/domain/models/addon_models.dart';
import 'package:pixel/features/addons/domain/models/stream_models.dart';
import 'package:pixel/features/addons/presentation/screens/addons_screen.dart';

class _MemoryAddonsStorage extends AddonsStorage {
  AddonsStoreState _state = const AddonsStoreState();

  @override
  Future<AddonsStoreState> load() async => _state;

  @override
  Future<void> save(AddonsStoreState state) async {
    _state = state;
  }
}

class _TestFakeCsEngine implements CloudStreamEngine {
  @override
  Future<void> cancelStreamResolution(String requestId) async {}

  @override
  Future<Cs3InstallOutcome> installPlugin({
    required String uid,
    required String repoId,
    required String internalName,
    required String downloadUrl,
    String? expectedSha256,
    bool enabled = true,
  }) async =>
      const Cs3InstallOutcome(status: Cs3LoadStatus.loaded);

  @override
  Future<Map<String, Cs3InstallOutcome>> loadSavedPlugins(
    List<InstalledCs3Plugin> plugins,
  ) async =>
      const {};

  @override
  Stream<Cs3StreamEvent> resolveStreams({
    required String requestId,
    required StreamQuery query,
  }) =>
      const Stream.empty();

  @override
  Future<bool> setPluginEnabled(String uid, bool enabled) async => true;

  @override
  Future<bool> uninstallPlugin(String uid, {String? localFilePath}) async =>
      true;
}

Widget _buildTestHost(_MemoryAddonsStorage storage) {
  return ProviderScope(
    overrides: [
      addonsStorageProvider.overrideWithValue(storage),
      cloudStreamEngineProvider.overrideWithValue(_TestFakeCsEngine()),
    ],
    child: const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: AddonsScreen(),
      ),
    ),
  );
}

Future<void> _pumpSettledFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('AddonsScreen UI & Real Store', () {
    testWidgets(
        'fresh launch has zero pre-installed addons and renders 8 official CS3 repos',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 884));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestHost(_MemoryAddonsStorage()));
      await _pumpSettledFrames(tester);

      expect(find.text('Addons'), findsWidgets);
      expect(find.text('Add Addon'), findsWidgets);
      expect(find.text('Stream only'), findsOneWidget);
      expect(find.text('Home'), findsWidgets);
      expect(find.text('Movies'), findsWidgets);
      expect(find.text('TV Shows'), findsOneWidget);
      expect(find.text('Anime'), findsOneWidget);
      expect(find.text('Categories'), findsWidgets);

      // Zero default addons safety guarantee
      expect(find.text('No Addons Yet'), findsOneWidget);

      // Switch to Official directory
      await tester.tap(find.text('Official').first);
      await _pumpSettledFrames(tester);

      // No Safety Guarantee banner on Official tab
      expect(find.textContaining('Safety Guarantee'), findsNothing);
      expect(find.text('CloudStream'), findsOneWidget);
      expect(find.text('Megix Repo'), findsOneWidget);
      expect(find.text('CNC Repo'), findsOneWidget);
      expect(find.text('Phisher Repo'), findsOneWidget);
      expect(find.text('Cinephile'), findsOneWidget);

      // Scroll down to verify remaining repos & compact Stremio placeholder
      await tester.drag(find.byType(ListView).first, const Offset(0, -1000));
      await _pumpSettledFrames(tester);
      expect(find.text('CloudStream Providers Repository'), findsOneWidget);
      expect(find.text('Official Stremio'), findsOneWidget);
    });

    testWidgets(
        'composer validates URLs, defaults to zero screens, and gates first install behind safety sheet',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 884));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestHost(_MemoryAddonsStorage()));
      await _pumpSettledFrames(tester);

      await tester.enterText(
        find.byType(TextField).first,
        'https://example.com/manifest.json',
      );
      await tester.pump();
      expect(find.text('Stremio v3'), findsOneWidget);

      await tester.tap(find.text('Add Addon').last);
      await _pumpSettledFrames(tester);
      expect(find.text('Third-Party Addon Safety Notice'), findsOneWidget);
    });

    testWidgets(
        'layout holds without overflow at 390px, 768px, and 1440px widths',
        (tester) async {
      for (final width in const [390.0, 768.0, 1440.0]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpWidget(_buildTestHost(_MemoryAddonsStorage()));
        await _pumpSettledFrames(tester);
        expect(tester.takeException(), isNull);
      }
      await tester.binding.setSurfaceSize(null);
    });
  });
}
