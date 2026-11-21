import 'dart:math' as math;

import '../../details/data/tmdb_models.dart';
import '../../home/data/models/meta_model.dart';

/// Compact on-device representation of a user's content taste built from their
/// Liked titles, My List items, and Disliked titles ("Not for me").
class UserTasteProfile {
  const UserTasteProfile({
    this.genreWeights = const {},
    this.dislikedGenrePenalties = const {},
    this.preferredYearCenter = 2020.0,
    this.isEmpty = true,
  });

  /// Normalized genre affinity weights in `[0.0, 1.0]`, keyed lowercase.
  final Map<String, double> genreWeights;

  /// Genre penalties in `[0.0, 0.25]` for disliked genres outside the user's top-2 likes.
  final Map<String, double> dislikedGenrePenalties;

  /// Recency-weighted center of release years the user interacts with.
  final double preferredYearCenter;

  /// True when the user has no cached Liked, My List, or Dislike signals.
  final bool isEmpty;

  /// Builds a lightweight profile from at most the 60 most recent entries in
  /// each list to guarantee `< 1 ms` runtime and negligible RAM usage.
  factory UserTasteProfile.fromInteractions({
    required List<MetaModel> likedMetas,
    required List<MetaModel> myListMetas,
    Map<String, int> dislikedGenreCounts = const {},
    bool isAnime = false,
  }) {
    final rawGenreWeights = <String, double>{};
    var yearWeightedSum = 0.0;
    var yearTotalWeight = 0.0;

    void accumulateList(List<MetaModel> list, double baseWeight) {
      final limit = list.length < 60 ? list.length : 60;
      for (var i = 0; i < limit; i++) {
        final meta = list[i];
        final recencyFactor = math.pow(0.92, i).toDouble();
        final w = baseWeight * recencyFactor;

        for (final rawGenre in meta.genres) {
          final g = _normalizeGenre(rawGenre);
          if (g.isEmpty) continue;
          rawGenreWeights[g] = (rawGenreWeights[g] ?? 0.0) + w;
        }

        final year = _parseYear(meta.releaseInfo);
        if (year != null && year >= 1950 && year <= 2035) {
          yearWeightedSum += year * w;
          yearTotalWeight += w;
        }
      }
    }

    accumulateList(likedMetas, 1.5);
    accumulateList(myListMetas, 1.0);

    var maxWeight = 0.0;
    for (final v in rawGenreWeights.values) {
      if (v > maxWeight) maxWeight = v;
    }

    final normalizedGenres = <String, double>{};
    if (maxWeight > 0) {
      for (final entry in rawGenreWeights.entries) {
        normalizedGenres[entry.key] = (entry.value / maxWeight).clamp(0.0, 1.0);
      }
    }

    // Protect the user's top-2 favorite genres from overly broad dislike penalties.
    final sortedPositive = normalizedGenres.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top2Protected = sortedPositive.take(2).map((e) => e.key).toSet();

    final penalties = <String, double>{};
    for (final entry in dislikedGenreCounts.entries) {
      final g = _normalizeGenre(entry.key);
      if (g.isEmpty || top2Protected.contains(g)) continue;
      penalties[g] = (entry.value * 0.10).clamp(0.0, 0.25);
    }

    final preferredYear =
        yearTotalWeight > 0 ? (yearWeightedSum / yearTotalWeight) : (isAnime ? 2021.0 : 2020.0);

    return UserTasteProfile(
      genreWeights: normalizedGenres,
      dislikedGenrePenalties: penalties,
      preferredYearCenter: preferredYear,
      isEmpty: normalizedGenres.isEmpty && penalties.isEmpty,
    );
  }

  /// Scores a genre list against the user's positive taste weights (`[0.0, 1.0]`).
  double scoreGenres(List<String> genres) {
    if (genreWeights.isEmpty || genres.isEmpty) return 0.25;
    final matched = <double>[];
    for (final raw in genres) {
      final w = genreWeights[_normalizeGenre(raw)];
      if (w != null && w > 0) matched.add(w);
    }
    if (matched.isEmpty) return 0.10;
    matched.sort((a, b) => b.compareTo(a));
    final top = matched.take(2).toList(growable: false);
    final sum = top.fold<double>(0.0, (a, b) => a + b);
    return (sum / top.length).clamp(0.0, 1.0);
  }

  /// Computes total negative penalty (`[0.0, 0.30]`) for disliked genres.
  double penaltyForGenres(List<String> genres) {
    if (dislikedGenrePenalties.isEmpty || genres.isEmpty) return 0.0;
    var total = 0.0;
    final seen = <String>{};
    for (final raw in genres) {
      final g = _normalizeGenre(raw);
      if (!seen.add(g)) continue;
      total += dislikedGenrePenalties[g] ?? 0.0;
    }
    return total.clamp(0.0, 0.30);
  }

  static String _normalizeGenre(String raw) {
    final g = raw.trim().toLowerCase();
    if (g == 'science fiction') return 'sci-fi';
    if (g == 'action & adventure') return 'action';
    if (g == 'sci-fi & fantasy') return 'sci-fi';
    if (g == 'war & politics') return 'war';
    return g;
  }

  static int? _parseYear(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(raw);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}

/// Aggregated multi-signal candidate container prior to final scoring.
class CandidateSignalData {
  CandidateSignalData({
    required this.item,
    this.hop1Rank,
    this.hop2BridgeCount = 0,
    this.hop2BestRankScore = 0.0,
    this.fromDiscover = false,
  });

  TmdbRecommendation item;
  int? hop1Rank;
  int hop2BridgeCount;
  double hop2BestRankScore;
  bool fromDiscover;
}

/// Lightweight, 3GB-RAM-friendly hybrid scoring engine combining:
/// 1. 2-Hop Collaborative Graph Co-Occurrence (`GraphScore`)
/// 2. Content & Keyword Discovery Similarity (`ContentScore`)
/// 3. Bayesian Quality & Modern-First Recency (`QualityRecencyScore`)
/// 4. Global On-Device User Taste Profile + Dislike Penalties (`65/35` blend)
/// 5. Franchise Stem Deduplication (Max 1 per franchise) + MMR Diversity
class RecommendationScoringEngine {
  RecommendationScoringEngine._();

  static final RegExp _trailingMarkerRegex = RegExp(
    r'\s+(?:part|chapter|vol\.?|volume|season|episode|book|act|series)\s*(?:\d+|[ivxlcdm]+|one|two|three|four|five|six|seven|eight|nine|ten)\b.*$',
    caseSensitive: false,
  );
  static final RegExp _trailingNumberRegex = RegExp(
    r'\s+(?:\d{1,2}|19\d{2}|20\d{2}|ii|iii|iv|vi|vii|viii|ix|x)$',
    caseSensitive: false,
  );
  static final RegExp _punctRegex = RegExp(r'[^a-z0-9\s]');
  static final RegExp _multiSpaceRegex = RegExp(r'\s+');

  /// Normalizes a movie/series/anime title into a canonical franchise stem so
  /// sequels, seasons, and spin-off subtitles collapse to the same key.
  static String normalizeFranchiseStem(String title) {
    var s = title.trim().toLowerCase();
    if (s.isEmpty) return '';

    // Truncate explicit sequel/season markers first (e.g. "Dune: Part Two", "Attack on Titan Season 2").
    s = s.replaceFirst(_trailingMarkerRegex, '').trim();

    // Truncate subtitle after ":" or " - " when the prefix is a meaningful title stem.
    final colonIdx = s.indexOf(':');
    if (colonIdx >= 4 && RegExp(r'[a-z]').hasMatch(s.substring(0, colonIdx))) {
      s = s.substring(0, colonIdx).trim();
    } else {
      final dashIdx = s.indexOf(' - ');
      if (dashIdx >= 4 && RegExp(r'[a-z]').hasMatch(s.substring(0, dashIdx))) {
        s = s.substring(0, dashIdx).trim();
      }
    }

    // Strip trailing sequel numerals or release-year suffixes ("Toy Story 3", "Blade Runner 2049").
    s = s.replaceFirst(_trailingNumberRegex, '').trim();
    s = s.replaceAll(_punctRegex, ' ').replaceAll(_multiSpaceRegex, ' ').trim();
    return s;
  }

  /// Enforces the Modern-First (2012+) gate with Iconic Classics & Seed-Era
  /// exceptions so obscure pre-2012 low-rated slop never pollutes rows.
  static bool passesModernOrClassicGate(
    TmdbRecommendation candidate, {
    int? seedReleaseYear,
    int? currentYear,
    bool relaxed = false,
  }) {
    if (candidate.title.trim().isEmpty) return false;
    final votes = candidate.voteCount;
    final rating = candidate.voteAverage ?? 0.0;
    final year = candidate.releaseYear;

    if (relaxed) {
      if (year != null && year < 2012) {
        return rating >= 7.0 && votes >= 250;
      }
      return votes >= 40 && rating >= 6.0;
    }

    if (year == null) {
      // Preserve candidates whose fixture omits release_date if they pass solid quality gates.
      return votes >= 150 && rating >= 6.3;
    }

    final nowYear = currentYear ?? DateTime.now().year;
    if (year >= 2012) {
      if (year >= nowYear - 1) {
        return votes >= 50 && rating >= 6.2;
      }
      return votes >= 150 && rating >= 6.3;
    }

    // Iconic Classics exception (e.g., The Dark Knight, Inception, The Matrix).
    if (rating >= 7.8 && votes >= 1500) return true;

    // Seed-Era exception: when the user liked an older title, allow strong era-matched picks.
    if (seedReleaseYear != null &&
        seedReleaseYear < 2012 &&
        (year - seedReleaseYear).abs() <= 8 &&
        rating >= 7.0 &&
        votes >= 350) {
      return true;
    }

    return false;
  }

  /// Ranks aggregated multi-signal candidates using the 65% Seed / 35% User
  /// Taste Profile blend, applies the Modern-First gate, caps franchises to 1
  /// entry per row, and enforces light MMR sub-genre diversity.
  static List<TmdbRecommendation> rankCandidates({
    required List<CandidateSignalData> candidates,
    required String seedTitle,
    required List<String> seedGenres,
    int? seedReleaseYear,
    String? seedOriginalLanguage,
    int? seedCollectionId,
    required UserTasteProfile tasteProfile,
    int limit = 36,
    int? currentYear,
  }) {
    if (candidates.isEmpty) return const [];
    final nowYear = currentYear ?? DateTime.now().year;

    // 1. Progressive quality gating (never leave a row empty on niche seeds).
    final filtered = <CandidateSignalData>[];
    final includedIds = <int>{};

    for (final c in candidates) {
      if (passesModernOrClassicGate(
        c.item,
        seedReleaseYear: seedReleaseYear,
        currentYear: nowYear,
      )) {
        filtered.add(c);
        includedIds.add(c.item.id);
      }
    }

    if (filtered.length < 8) {
      for (final c in candidates) {
        if (filtered.length >= 16) break;
        if (includedIds.contains(c.item.id)) continue;
        if (passesModernOrClassicGate(
          c.item,
          seedReleaseYear: seedReleaseYear,
          currentYear: nowYear,
          relaxed: true,
        )) {
          filtered.add(c);
          includedIds.add(c.item.id);
        }
      }
    }

    if (filtered.length < 2) {
      for (final c in candidates) {
        if (filtered.length >= 8) break;
        if (includedIds.contains(c.item.id)) continue;
        if (c.item.voteCount >= 15 || c.item.popularity > 0) {
          filtered.add(c);
          includedIds.add(c.item.id);
        }
      }
    }

    if (filtered.isEmpty) return const [];

    // 2. Score every surviving candidate.
    final normalizedSeedGenres =
        seedGenres.map(UserTasteProfile._normalizeGenre).where((g) => g.isNotEmpty).toSet();
    final seedLang = seedOriginalLanguage?.trim().toLowerCase();

    final scored = <({CandidateSignalData data, double score})>[];
    for (final c in filtered) {
      final r = c.item;

      // Signal A: 2-Hop Graph Co-Occurrence Score [0..1]
      var graphScore = 0.0;
      final hasGraphHit = c.hop1Rank != null || c.hop2BridgeCount > 0;
      if (c.hop1Rank != null) {
        graphScore += 0.68 / (1.0 + c.hop1Rank! * 0.08);
      }
      if (c.hop2BridgeCount > 0) {
        graphScore += math.min(0.42, c.hop2BridgeCount * 0.16 + c.hop2BestRankScore * 0.10);
      }
      if (hasGraphHit && c.fromDiscover) {
        graphScore += 0.12;
      } else if (!hasGraphHit && c.fromDiscover) {
        graphScore = 0.48;
      }
      graphScore = graphScore.clamp(0.0, 1.0);

      // Signal B: Content & Thematic Keyword Score [0..1]
      double contentScore;
      if (normalizedSeedGenres.isEmpty && seedLang == null) {
        contentScore = c.fromDiscover ? 0.65 : 0.50;
      } else {
        final candGenres = r.genres
            .map(UserTasteProfile._normalizeGenre)
            .where((g) => g.isNotEmpty)
            .toSet();
        var genreOverlap = 0.45;
        if (normalizedSeedGenres.isNotEmpty && candGenres.isNotEmpty) {
          final overlap = candGenres.intersection(normalizedSeedGenres).length;
          final denom = math.max(1, math.min(candGenres.length, normalizedSeedGenres.length));
          genreOverlap = (overlap / denom).clamp(0.0, 1.0);
        }
        final discoverSignal = c.fromDiscover ? 1.0 : 0.40;
        final candLang = r.originalLanguage?.trim().toLowerCase();
        final langSignal =
            (seedLang == null || candLang == null || candLang == seedLang) ? 1.0 : 0.30;
        contentScore =
            (0.65 * genreOverlap + 0.20 * discoverSignal + 0.15 * langSignal).clamp(0.0, 1.0);
      }

      // Signal C: Bayesian Quality, Modern Recency & Popularity [0..1]
      final votes = r.voteCount.toDouble();
      final avg = r.voteAverage ?? 6.5;
      final bayesian = ((votes / (votes + 250.0)) * avg) + ((250.0 / (votes + 250.0)) * 6.7);
      final qualityNorm = ((bayesian - 5.5) / 3.5).clamp(0.0, 1.0);

      double recencyNorm;
      final year = r.releaseYear;
      if (year == null) {
        recencyNorm = 0.65;
      } else if (year >= 2020) {
        final span = math.max(1, nowYear - 2020);
        recencyNorm = 0.90 + 0.10 * ((math.min(year, nowYear) - 2020) / span);
      } else if (year >= 2012) {
        recencyNorm = 0.65 + 0.25 * ((year - 2012) / 8.0);
      } else {
        recencyNorm = 0.60;
      }

      final popNorm =
          (math.log(1.0 + math.max(0.0, r.popularity)) / math.log(1.0 + 250.0)).clamp(0.0, 1.0);
      final qualityRecencyScore =
          (0.50 * qualityNorm + 0.30 * recencyNorm + 0.20 * popNorm).clamp(0.0, 1.0);

      final seedAffinity =
          (0.45 * graphScore + 0.30 * contentScore + 0.25 * qualityRecencyScore).clamp(0.0, 1.0);

      // Global Taste Blend (65% Seed / 35% Taste - Dislike Penalty)
      double tasteScore;
      if (tasteProfile.isEmpty) {
        tasteScore = seedAffinity;
      } else {
        final genreTaste = tasteProfile.scoreGenres(r.genres);
        final eraTaste = year == null
            ? 0.60
            : (1.0 - (year - tasteProfile.preferredYearCenter).abs() / 25.0).clamp(0.2, 1.0);
        tasteScore = (0.80 * genreTaste + 0.20 * eraTaste).clamp(0.0, 1.0);
      }
      final dislikePenalty = tasteProfile.penaltyForGenres(r.genres);
      final finalScore = (0.65 * seedAffinity + 0.35 * tasteScore - dislikePenalty).clamp(0.0, 1.0);

      scored.add((data: c, score: finalScore));
    }

    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return b.data.item.popularity.compareTo(a.data.item.popularity);
    });

    // 3. Franchise Stem & Collection Deduplication (Max 1 per franchise per row).
    final seedStem = normalizeFranchiseStem(seedTitle);
    final seenStems = <String>{
      if (seedStem.isNotEmpty && scored.length > 4) seedStem,
    };
    final seenCollections = <int>{
      if (seedCollectionId != null && scored.length > 4) seedCollectionId,
    };

    final deduped = <({CandidateSignalData data, double score})>[];
    for (final entry in scored) {
      final r = entry.data.item;
      final stem = normalizeFranchiseStem(r.title);
      if (stem.isNotEmpty && seenStems.contains(stem)) continue;
      if (r.collectionId != null && seenCollections.contains(r.collectionId)) continue;
      if (stem.isNotEmpty) seenStems.add(stem);
      if (r.collectionId != null) seenCollections.add(r.collectionId!);
      deduped.add(entry);
    }

    if (deduped.length <= 2 || (tasteProfile.isEmpty && normalizedSeedGenres.isEmpty)) {
      return [for (final e in deduped.take(limit)) e.data.item];
    }

    // 4. Greedy Maximal Marginal Relevance (MMR) for sub-genre variety across the row.
    final selected = <TmdbRecommendation>[deduped.first.data.item];
    final selectedGenresWindow = <Set<String>>[
      deduped.first.data.item.genres.map(UserTasteProfile._normalizeGenre).toSet(),
    ];
    final remaining = deduped.sublist(1);

    while (remaining.isNotEmpty && selected.length < limit) {
      var bestIdx = 0;
      var bestMmr = -999.0;

      // Only examine top 24 remaining candidates per step for strict O(1)-bounded CPU work.
      final inspectLimit = remaining.length < 24 ? remaining.length : 24;
      for (var i = 0; i < inspectLimit; i++) {
        final cand = remaining[i];
        final candGenres = cand.data.item.genres.map(UserTasteProfile._normalizeGenre).toSet();

        var maxOverlap = 0.0;
        if (candGenres.isNotEmpty) {
          for (final prevGenres in selectedGenresWindow) {
            if (prevGenres.isEmpty) continue;
            final overlap = candGenres.intersection(prevGenres).length /
                math.max(1, math.min(candGenres.length, prevGenres.length));
            if (overlap > maxOverlap) maxOverlap = overlap;
          }
        }

        final mmr = (0.85 * cand.score) - (0.15 * maxOverlap);
        if (mmr > bestMmr) {
          bestMmr = mmr;
          bestIdx = i;
        }
      }

      final chosen = remaining.removeAt(bestIdx);
      selected.add(chosen.data.item);
      selectedGenresWindow.add(
        chosen.data.item.genres.map(UserTasteProfile._normalizeGenre).toSet(),
      );
      if (selectedGenresWindow.length > 2) {
        selectedGenresWindow.removeAt(0);
      }
    }

    return selected;
  }

  /// Smart Daily Seed Selection: weights recency in Liked/My List, Taste Profile
  /// genre centrality, and IMDb rating quality, then hashes deterministically within
  /// the top tier while avoiding [yesterdayId] and [avoidSourceId].
  static MetaModel selectSmartDailySeed({
    required List<MetaModel> candidates,
    required UserTasteProfile tasteProfile,
    required String dateKey,
    required String bucketKey,
    String? yesterdayId,
    String? avoidSourceId,
  }) {
    assert(candidates.isNotEmpty);
    if (candidates.length == 1) return candidates.first;

    final ranked = <({MetaModel meta, double score, int originalIdx})>[];
    for (var i = 0; i < candidates.length; i++) {
      final m = candidates[i];
      final recencyScore = math.pow(0.90, i).toDouble();
      final tasteScore = tasteProfile.scoreGenres(m.genres);
      final parsedRating = double.tryParse(m.imdbRating ?? '') ?? 7.0;
      final qualityScore = ((parsedRating - 5.0) / 5.0).clamp(0.0, 1.0);
      final seedScore = 0.50 * recencyScore + 0.30 * tasteScore + 0.20 * qualityScore;
      ranked.add((meta: m, score: seedScore, originalIdx: i));
    }

    ranked.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.originalIdx.compareTo(b.originalIdx);
    });

    final tierSize = candidates.length <= 4
        ? candidates.length
        : math.max(3, (candidates.length * 0.65).ceil());
    final topTier = [for (final r in ranked.take(tierSize)) r.meta];

    final seed = _stableHash('$dateKey:$bucketKey');
    final startIdx = seed % topTier.length;
    var chosen = topTier[startIdx];

    for (var offset = 0; offset < topTier.length; offset++) {
      final c = topTier[(startIdx + offset) % topTier.length];
      final repeatsYesterday = yesterdayId != null && c.id == yesterdayId;
      final collidesWithPair = avoidSourceId != null && c.id == avoidSourceId;
      if (!repeatsYesterday && !collidesWithPair) {
        return c;
      }
    }

    // Fall back to full candidate list if top tier only contained yesterday/paired picks.
    for (final c in candidates) {
      final repeatsYesterday = yesterdayId != null && c.id == yesterdayId;
      final collidesWithPair = avoidSourceId != null && c.id == avoidSourceId;
      if (!repeatsYesterday && !collidesWithPair) {
        return c;
      }
    }

    if (avoidSourceId != null && chosen.id == avoidSourceId) {
      chosen = candidates.firstWhere(
        (c) => c.id != avoidSourceId,
        orElse: () => chosen,
      );
    }
    return chosen;
  }

  /// Re-ranks resolved Anime [MetaModel] items using 65% upstream 2-hop AniList
  /// rank affinity + 35% User Anime Taste Profile and deduplicates anime franchises.
  static List<MetaModel> rerankAndDeduplicateAnimeMetas({
    required List<MetaModel> candidates,
    required String seedTitle,
    required UserTasteProfile tasteProfile,
    int limit = 36,
  }) {
    if (candidates.isEmpty) return const [];

    final scored = <({MetaModel meta, double score, int idx})>[];
    for (var i = 0; i < candidates.length; i++) {
      final m = candidates[i];
      final upstreamRankScore = 1.0 / (1.0 + i * 0.08);
      final tasteScore = tasteProfile.isEmpty
          ? upstreamRankScore
          : tasteProfile.scoreGenres(m.genres);
      final penalty = tasteProfile.penaltyForGenres(m.genres);
      final blended = (0.65 * upstreamRankScore + 0.35 * tasteScore - penalty).clamp(0.0, 1.0);
      scored.add((meta: m, score: blended, idx: i));
    }

    if (!tasteProfile.isEmpty) {
      scored.sort((a, b) {
        final cmp = b.score.compareTo(a.score);
        if (cmp != 0) return cmp;
        return a.idx.compareTo(b.idx);
      });
    }

    final seedStem = normalizeFranchiseStem(seedTitle);
    final seenStems = <String>{
      if (seedStem.isNotEmpty && scored.length > 4) seedStem,
    };

    final out = <MetaModel>[];
    for (final entry in scored) {
      if (out.length >= limit) break;
      final stem = normalizeFranchiseStem(entry.meta.name);
      if (stem.isNotEmpty && seenStems.contains(stem)) continue;
      if (stem.isNotEmpty) seenStems.add(stem);
      out.add(entry.meta);
    }
    return out;
  }

  static int _stableHash(String input) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
