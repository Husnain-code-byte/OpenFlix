import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/user_error.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../player/domain/models/player_models.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../../domain/models/addon_models.dart';
import '../../domain/models/stream_models.dart';
import '../controllers/addons_controller.dart';
import '../controllers/stream_resolver_controller.dart';
import '../screens/addons_screen.dart';
import 'addons_ui_kit.dart';

/// Opens the live Stream Sources verification bottom sheet for [query].
/// Fans out across all enabled Stremio stream/subtitle addons and loaded
/// CloudStream `.cs3` providers until the built-in video player milestone lands.
Future<void> showStreamSourcesSheet(
  BuildContext context, {
  required StreamQuery query,
}) =>
    showAddonsSheet<void>(
      context,
      builder: (_) => _StreamSourcesSheet(query: query),
    );

class _StreamSourcesSheet extends ConsumerStatefulWidget {
  const _StreamSourcesSheet({required this.query});

  final StreamQuery query;

  @override
  ConsumerState<_StreamSourcesSheet> createState() =>
      _StreamSourcesSheetState();
}

class _StreamSourcesSheetState extends ConsumerState<_StreamSourcesSheet> {
  late final StreamResolverController _resolver;

  @override
  void initState() {
    super.initState();
    _resolver = ref.read(streamResolverProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(hasAnyStreamSourceProvider)) {
        _resolver.resolve(widget.query);
      }
    });
  }

  @override
  void dispose() {
    Future<void>.microtask(() => _resolver.cancel());
    super.dispose();
  }

  void _openAddonsScreen() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push<void>(addonsRoute<void>(const AddonsScreen()));
  }

  Future<void> _copyTarget(String target, {required bool isMagnet}) async {
    addonHaptic(AddonHaptic.light);
    await Clipboard.setData(ClipboardData(text: target));
    if (!mounted) return;
    showAddonsToast(
      context,
      isMagnet ? 'Magnet URI copied to clipboard' : 'Stream URL copied',
    );
  }

  void _playInternally(ResolvedStream stream) {
    addonHaptic(AddonHaptic.light);
    final nav = Navigator.of(context);
    nav.pop();
    nav.push<void>(
      openFlixPlayerRoute(
        PlaybackLaunchArgs(
          query: widget.query,
          initialStream: stream,
        ),
      ),
    );
  }

  Future<void> _openExternally(String target) async {
    addonHaptic(AddonHaptic.selection);
    final ok =
        await ref.read(addonsControllerProvider.notifier).openExternalUrl(target);
    if (!mounted) return;
    if (!ok) {
      showAddonsToast(
        context,
        'No external app found to open this stream link',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAnySource = ref.watch(hasAnyStreamSourceProvider);
    final resolverState = ref.watch(streamResolverProvider);
    final subtitleText = widget.query.displaySubtitle.isNotEmpty
        ? widget.query.displaySubtitle
        : (widget.query.mediaType == 'series'
            ? 'Series Stream Lookup'
            : 'Movie Stream Lookup');

    return AddonsSheetFrame(
      maxHeightFactor: 0.92,
      header: Row(
        children: [
          AddonMonogram(
            label: widget.query.title,
            size: 40,
            kindGlyph: AddonIcons.play,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.query.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AddonsText.inter(
                    16.5,
                    weight: FontWeight.w700,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AddonsText.inter(
                        12,
                        color: AddonsColors.textMuted,
                        tabular: true,
                      ),
                    ),
                    if (hasAnySource)
                      AddonBadge(
                        resolverState.isResolving
                            ? '${resolverState.streams.length} found...'
                            : '${resolverState.streams.length} stream${resolverState.streams.length == 1 ? '' : 's'}',
                        tone: resolverState.streams.isNotEmpty
                            ? AddonBadgeTone.live
                            : AddonBadgeTone.neutral,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (hasAnySource) ...[
            const SizedBox(width: 8),
            AddonPressable(
              borderRadius: 999,
              color: AddonsColors.card,
              borderColor: AddonsColors.hairline,
              semanticLabel: 'Refresh stream lookup',
              onTap: () => _resolver.resolve(widget.query),
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: AddonIcon(
                    AddonIcons.refresh,
                    size: 15,
                    color: AddonsColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      body: !hasAnySource
          ? Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
              child: AppStatusCard.noAddons(
                onInstallAddons: _openAddonsScreen,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (resolverState.providerStatuses.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                    child: SizedBox(
                      height: 30,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: resolverState.providerStatuses.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, i) => _ProviderStatusPill(
                          status: resolverState.providerStatuses[i],
                        ),
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: _buildBodyList(context, resolverState),
                ),
              ],
            ),
      footer: !hasAnySource
          ? null
          : Row(
              children: [
                Expanded(
                  child: Text(
                    resolverState.subtitles.isEmpty
                        ? 'Tap any playable stream to watch in OpenFlix player.'
                        : '${resolverState.subtitles.length} subtitle track${resolverState.subtitles.length == 1 ? '' : 's'} matched · Tap Play to watch in OpenFlix.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AddonsText.inter(
                      11,
                      color: AddonsColors.textMuted,
                      height: 1.35,
                      tabular: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AddonsButton(
                  label: 'Addons',
                  iconSvg: AddonIcons.gear,
                  variant: AddonButtonVariant.secondary,
                  expand: false,
                  compact: true,
                  height: 36,
                  onTap: _openAddonsScreen,
                ),
              ],
            ),
    );
  }

  Widget _buildBodyList(
    BuildContext context,
    StreamResolverState resolverState,
  ) {
    if (resolverState.isResolving && resolverState.streams.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 16),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => const _StreamCardSkeleton(),
      );
    }

    if (!resolverState.isResolving && resolverState.streams.isEmpty) {
      final err = resolverState.error != null
          ? UserError.from(
              resolverState.error,
              fallbackType: UserErrorType.noStreams,
              logTag: 'StreamSourcesSheet',
            )
          : UserError.noStreams();
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 16),
        child: AppStatusCard.fromError(
          err,
          onAction: () => _resolver.resolve(widget.query),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 2, 24, 16),
      itemCount: resolverState.streams.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final stream = resolverState.streams[i];
        return _ResolvedStreamCard(
          stream: stream,
          globalSubtitlesCount: resolverState.subtitles.length,
          onCopy: (target) => _copyTarget(
            target,
            isMagnet: stream.transport == StreamTransport.torrent,
          ),
          onPlayInternal: stream.canPlayInternally
              ? () => _playInternally(stream)
              : null,
          onOpenExternal: _openExternally,
        );
      },
    );
  }
}

class _ProviderStatusPill extends StatelessWidget {
  const _ProviderStatusPill({required this.status});

  final ProviderResolutionStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color border, Color text) = switch (status.state) {
      ProviderStatusKind.loading =>
        (AddonsColors.hairlineStrong, AddonsColors.textSecondary),
      ProviderStatusKind.done => (AddonsColors.liveBorder, AddonsColors.live),
      ProviderStatusKind.empty => (AddonsColors.hairline, AddonsColors.textFaint),
      ProviderStatusKind.error =>
        (AddonsColors.dangerHairline, AddonsColors.dangerText),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AddonsColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AddonIcon(
            status.architecture == AddonArchitecture.cloudstream
                ? AddonIcons.cloud
                : AddonIcons.play,
            size: 11,
            color: text,
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              status.sourceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AddonsText.inter(11, weight: FontWeight.w600, color: text),
            ),
          ),
          const SizedBox(width: 6),
          switch (status.state) {
            ProviderStatusKind.loading => SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: text),
              ),
            ProviderStatusKind.done => Text(
                status.elapsedMs != null
                    ? '${status.streamCount} · ${status.elapsedMs}ms'
                    : '${status.streamCount}',
                style: AddonsText.inter(
                  10,
                  weight: FontWeight.w700,
                  color: text,
                  tabular: true,
                ),
              ),
            ProviderStatusKind.empty => Text(
                '0',
                style: AddonsText.inter(10, color: text, tabular: true),
              ),
            ProviderStatusKind.error => Text(
                'Err',
                style: AddonsText.inter(10, weight: FontWeight.w700, color: text),
              ),
          },
        ],
      ),
    );
  }
}

class _ResolvedStreamCard extends StatelessWidget {
  const _ResolvedStreamCard({
    required this.stream,
    required this.globalSubtitlesCount,
    required this.onCopy,
    required this.onPlayInternal,
    required this.onOpenExternal,
  });

  final ResolvedStream stream;
  final int globalSubtitlesCount;
  final ValueChanged<String> onCopy;
  final VoidCallback? onPlayInternal;
  final ValueChanged<String> onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final target = stream.playableOrCopyableTarget;
    final canPlayInternal = onPlayInternal != null && stream.canPlayInternally;
    final hasHeaders = stream.headers.isNotEmpty ||
        (stream.referer != null && stream.referer!.isNotEmpty);
    final sizeLabel = stream.formattedSize;
    final subsCount = stream.subtitles.isNotEmpty
        ? stream.subtitles.length
        : globalSubtitlesCount;

    return GestureDetector(
      onTap: canPlayInternal ? onPlayInternal : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AddonsColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: canPlayInternal
                ? AddonsColors.hairlineStrong
                : AddonsColors.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (stream.qualityLabel != null && stream.qualityLabel!.isNotEmpty)
                  AddonBadge(
                    stream.qualityLabel!,
                    tone: stream.qualityRank >= 1080
                        ? AddonBadgeTone.live
                        : AddonBadgeTone.caution,
                  ),
                AddonBadge(
                  stream.transport.badgeLabel,
                  tone: canPlayInternal
                      ? AddonBadgeTone.live
                      : (stream.transport == StreamTransport.torrent
                          ? AddonBadgeTone.caution
                          : AddonBadgeTone.neutral),
                ),
                AddonBadge(
                  stream.architecture == AddonArchitecture.cloudstream
                      ? 'CS3 · ${stream.providerName}'
                      : stream.providerName,
                ),
                if (sizeLabel != null)
                  Text(
                    sizeLabel,
                    style: AddonsText.inter(
                      10.5,
                      color: AddonsColors.textMuted,
                      tabular: true,
                    ),
                  ),
                if (subsCount > 0)
                  AddonTag(
                    '$subsCount subs',
                    iconSvg: AddonIcons.subtitles,
                    dense: true,
                  ),
                if (hasHeaders) const AddonTag('Headers', dense: true),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              stream.title.isNotEmpty ? stream.title : stream.addonName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AddonsText.inter(
                13.5,
                weight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            if ((stream.description != null && stream.description!.isNotEmpty) ||
                (stream.filename != null && stream.filename!.isNotEmpty)) ...[
              const SizedBox(height: 4),
              Text(
                stream.description?.isNotEmpty == true
                    ? stream.description!
                    : stream.filename!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AddonsText.inter(
                  11.5,
                  color: AddonsColors.textMuted,
                  height: 1.4,
                ),
              ),
            ],
            if (target != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AddonsButton(
                      label: stream.transport == StreamTransport.torrent
                          ? 'Copy Magnet'
                          : 'Copy Link',
                      iconSvg: AddonIcons.copy,
                      variant: AddonButtonVariant.secondary,
                      height: 34,
                      compact: true,
                      onTap: () => onCopy(target),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: canPlayInternal
                        ? AddonsButton(
                            label: 'Play',
                            iconSvg: AddonIcons.play,
                            variant: AddonButtonVariant.primary,
                            height: 34,
                            compact: true,
                            onTap: onPlayInternal!,
                          )
                        : AddonsButton(
                            label: 'Open Externally',
                            iconSvg: AddonIcons.globe,
                            variant: AddonButtonVariant.primary,
                            height: 34,
                            compact: true,
                            onTap: () => onOpenExternal(target),
                          ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StreamCardSkeleton extends StatelessWidget {
  const _StreamCardSkeleton();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AddonsColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AddonsColors.hairline),
        ),
        child: const AddonShimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AddonSkeletonBox(width: 44, height: 18, radius: 6),
                  SizedBox(width: 6),
                  AddonSkeletonBox(width: 52, height: 18, radius: 6),
                  SizedBox(width: 6),
                  AddonSkeletonBox(width: 86, height: 18, radius: 6),
                ],
              ),
              SizedBox(height: 10),
              AddonSkeletonBox(width: 220, height: 14, radius: 4),
              SizedBox(height: 6),
              AddonSkeletonBox(width: 170, height: 12, radius: 4),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: AddonSkeletonBox(height: 34, radius: 10)),
                  SizedBox(width: 8),
                  Expanded(child: AddonSkeletonBox(height: 34, radius: 10)),
                ],
              ),
            ],
          ),
        ),
      );
}
