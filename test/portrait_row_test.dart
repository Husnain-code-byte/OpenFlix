import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/core/perf/snap_physics.dart';
import 'package:pixel/core/theme/app_theme.dart';
import 'package:pixel/core/utils/responsive.dart';
import 'package:pixel/features/home/data/models/meta_model.dart';
import 'package:pixel/features/home/presentation/widgets/poster_card.dart';
import 'package:pixel/features/home/presentation/widgets/poster_row.dart';

void main() {
  final metas = List.generate(
    6,
    (i) => MetaModel(id: 'test-$i', type: 'movie', name: 'Movie $i'),
  );

  testWidgets(
      'portrait cards stay 100% identical (113x170, 8px gap, 7px radius) on reference viewport',
      (tester) async {
    const refSize = Size(Responsive.referenceWidth, Responsive.referenceHeight);
    await tester.binding.setSurfaceSize(refSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: PosterRow(
            title: 'For You',
            metas: metas,
            onTapMeta: (_) {},
          ),
        ),
      ),
    ));

    expect(Responsive.sw, closeTo(1.0, 1e-6));
    expect(Responsive.sh, closeTo(1.0, 1e-6));

    final cards = find.byType(PosterCard);
    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    final third = tester.getRect(cards.at(2));
    final fourth = tester.getRect(cards.at(3));

    expect(first.width, closeTo(113.0, 0.01));
    expect(first.height, closeTo(170.0, 0.01));
    expect(second.width, closeTo(113.0, 0.01));
    expect(second.height, closeTo(170.0, 0.01));
    expect(first.left, closeTo(8.0, 0.01));
    expect(second.left - first.right, closeTo(8.0, 0.01));
    expect(AppDimens.posterRadius, closeTo(7.0, 0.01));
    expect(third.right, lessThan(refSize.width));
    expect(fourth.left, lessThan(refSize.width));
    expect(tester.takeException(), isNull);
  });

  const viewports = <Size>[
    Size(360, 780),
    Size(390, 844),
    Size(412, 915),
    Size(430, 932),
  ];

  for (final vp in viewports) {
    for (final customInset in <double?>[null, 16.0]) {
      testWidgets(
          'portrait cards scale proportionally and preserve 3-cards + right-edge peek at ${vp.width.toInt()}x${vp.height.toInt()} dp (inset: ${customInset ?? "default"})',
          (tester) async {
        await tester.binding.setSurfaceSize(vp);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: PosterRow(
                title: 'For You',
                metas: metas,
                inset: customInset,
                onTapMeta: (_) {},
              ),
            ),
          ),
        ));

        final expectedSw =
            (vp.width / Responsive.referenceWidth).clamp(0.82, 1.25);
        expect(Responsive.sw, closeTo(expectedSw, 0.001));

        final cards = find.byType(PosterCard);
        final first = tester.getRect(cards.at(0));
        final second = tester.getRect(cards.at(1));
        final third = tester.getRect(cards.at(2));
        final fourth = tester.getRect(cards.at(3));

        expect(first.width, closeTo(AppDimens.posterWidth, 0.01));
        expect(first.height, closeTo(AppDimens.posterHeight, 0.01));
        expect(second.width, closeTo(AppDimens.posterWidth, 0.01));
        expect(second.height, closeTo(AppDimens.posterHeight, 0.01));
        expect(
          first.left,
          closeTo(customInset ?? AppDimens.screenPadding, 0.01),
        );
        expect(second.left - first.right, closeTo(AppDimens.posterGap, 0.01));
        expect(AppDimens.posterRadius, closeTo(7.0 * expectedSw, 0.01));

        // 3 full cards visible + 4th card peeking on the right edge on every phone size
        expect(third.right, lessThan(vp.width));
        expect(fourth.left, lessThan(vp.width));
        expect(fourth.right, greaterThan(vp.width));

        // Verify dynamic PosterSnapPhysics stride equals scaled posterWidth + posterGap
        final listView = tester.widget<ListView>(find.byType(ListView));
        final snapPhysics = listView.physics as PosterSnapPhysics;
        expect(snapPhysics.itemExtent, closeTo(AppDimens.posterStride, 0.01));

        expect(tester.takeException(), isNull);
      });
    }
  }
}