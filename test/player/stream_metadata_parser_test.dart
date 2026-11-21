import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/addons/domain/models/addon_models.dart';
import 'package:pixel/features/addons/domain/models/stream_models.dart';
import 'package:pixel/features/player/data/stream_metadata_parser.dart';
import 'package:pixel/features/player/domain/models/ranked_stream.dart';

void main() {
  group('StreamMetadataParser', () {
    test('parses CloudStream flat strings, providerLang, and resolution', () {
      const stream = ResolvedStream(
        id: 'cs3_1',
        architecture: AddonArchitecture.cloudstream,
        addonId: 'megix/CineStream',
        addonName: 'CineStream',
        providerName: 'HDHub4u',
        providerLang: 'uni',
        title: 'HDHub4u | Hindi-English Dual Audio 1080p HEVC 10bit DD+ 5.1',
        transport: StreamTransport.directHttp,
        url: 'https://cdn.example.com/movie.mkv',
        qualityRank: 1080,
      );

      final parsed = StreamMetadataParser.parse(stream, mediaTitle: 'Dune');
      expect(parsed.detectedAudioLanguages, containsAll(['hi', 'en']));
      expect(parsed.isMultiAudio, isTrue);
      expect(parsed.resolutionHeight, 1080);
      expect(parsed.videoCodec, VideoCodecHint.hevc);
      expect(parsed.audioCodec, AudioCodecHint.eac3);
      expect(parsed.audioChannels, '5.1');
    });

    test('parses Stremio Torrentio multi-line metadata with flags, HDR, Atmos, and CAM', () {
      const stream = ResolvedStream(
        id: 'stremio_1',
        architecture: AddonArchitecture.stremio,
        addonId: 'torrentio',
        addonName: 'Torrentio',
        providerName: 'RD+ 4K',
        title: 'Torrentio\n4K DV HDR10+ WEB-DL',
        description: '🇮🇳 🇺🇸 Hindi + Eng · Atmos 7.1 · x265 · 💾 14.2 GB',
        transport: StreamTransport.directHttp,
        url: 'https://debrid.example.com/stream.mkv',
      );

      final parsed = StreamMetadataParser.parse(stream, mediaTitle: 'Avatar');
      expect(parsed.detectedAudioLanguages, containsAll(['hi', 'en']));
      expect(parsed.resolutionHeight, 2160);
      expect(parsed.hdrFormat, HdrFormat.dolbyVision);
      expect(parsed.videoCodec, VideoCodecHint.hevc);
      expect(parsed.audioCodec, AudioCodecHint.atmos);
      expect(parsed.audioChannels, '7.1');
      expect(parsed.releaseSource, ReleaseSourceHint.webDl);
    });

    test('does not misclassify subtitle tags or media title words as audio languages', () {
      const stream = ResolvedStream(
        id: 'stremio_2',
        architecture: AddonArchitecture.stremio,
        addonId: 'nuvio',
        addonName: 'Nuvio',
        providerName: 'Server1',
        title: 'The English Patient 1080p ESub Hindi Sub',
        transport: StreamTransport.hls,
        url: 'https://cdn.example.com/master.m3u8',
      );

      final parsed = StreamMetadataParser.parse(
        stream,
        mediaTitle: 'The English Patient',
      );
      expect(parsed.detectedAudioLanguages, isEmpty);
      expect(parsed.detectedSubtitleLanguages, containsAll(['en', 'hi']));
      expect(parsed.resolutionHeight, 1080);
    });

    test('uses CloudStream providerLang when descriptor omits explicit language', () {
      const stream = ResolvedStream(
        id: 'cs3_2',
        architecture: AddonArchitecture.cloudstream,
        addonId: 'phisher/Anichi',
        addonName: 'Anichi',
        providerName: 'AllAnime',
        providerLang: 'ja',
        title: 'HLS Server 720p',
        transport: StreamTransport.hls,
        url: 'https://cdn.example.com/ep1.m3u8',
        qualityRank: 720,
      );

      final parsed = StreamMetadataParser.parse(stream, mediaTitle: 'Bleach');
      expect(parsed.detectedAudioLanguages, {'ja'});
      expect(parsed.resolutionHeight, 720);
    });

    test('flags CAM/HDTS releases accurately', () {
      const stream = ResolvedStream(
        id: 'cam_1',
        architecture: AddonArchitecture.stremio,
        addonId: 'comet',
        addonName: 'Comet',
        providerName: 'Comet',
        title: 'Movie.2026.1080p.HDTS.Hindi.x264',
        transport: StreamTransport.directHttp,
        url: 'https://cdn.example.com/cam.mp4',
      );

      final parsed = StreamMetadataParser.parse(stream);
      expect(parsed.releaseSource, ReleaseSourceHint.camTs);
      expect(parsed.detectedAudioLanguages, {'hi'});
    });
  });
}
