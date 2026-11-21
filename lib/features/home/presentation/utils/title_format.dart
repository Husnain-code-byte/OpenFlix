/// Maps real addon metadata onto the Figma "Featured film" text layout.
class TitleParts {
  const TitleParts(this.lead, [this.connector, this.finish]);
  final String lead;
  final String? connector;
  final String? finish;
}

const _connectors = {
  'of', 'and', '&', 'the', 'vs', 'vs.', 'in', 'at', 'on', 'to', 'for', 'with',
  'de', 'la', 'el', 'le', 'von', 'van', 'der', 'du', 'des', 'y', 'e', 'und',
};

String _clean(String s) =>
    s.replaceAll(RegExp(r'[\s:;,\-–—]+$'), '').replaceAll(RegExp(r'^[\s\-–—]+'), '');

/// LEAD (34/37) · rule — CONNECTOR — rule · FINISH (23/28).
/// "Echoes of Tomorrow" → ECHOES / OF / TOMORROW
TitleParts splitTitle(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.length <= 1) return TitleParts(_clean(name).toUpperCase());

  // 1. First connector word with text on both sides
  for (var i = 1; i < words.length - 1; i++) {
    if (_connectors.contains(words[i].toLowerCase())) {
      return TitleParts(
        _clean(words.sublist(0, i).join(' ')).toUpperCase(),
        words[i].toUpperCase(),
        _clean(words.sublist(i + 1).join(' ')).toUpperCase(),
      );
    }
  }

  // 2. Otherwise split at the word boundary closest to the middle
  final total = words.join(' ').length;
  var split = 1;
  var bestDiff = 1 << 30;
  for (var i = 1; i < words.length; i++) {
    final a = words.sublist(0, i).join(' ').length;
    final diff = (a - (total - a)).abs();
    if (diff < bestDiff) {
      split = i;
      bestDiff = diff;
    }
  }
  return TitleParts(
    _clean(words.sublist(0, split).join(' ')).toUpperCase(),
    null,
    _clean(words.sublist(split).join(' ')).toUpperCase(),
  );
}

/// "129 min" → "2h 09m", "45 min" → "45m"
String? formatRuntime(String? rt) {
  if (rt == null || rt.trim().isEmpty) return null;
  final h = RegExp(r'(\d+)\s*h', caseSensitive: false).firstMatch(rt);
  final m = RegExp(r'(\d+)\s*m', caseSensitive: false).firstMatch(rt);
  var total = (h != null ? int.parse(h.group(1)!) * 60 : 0) + (m != null ? int.parse(m.group(1)!) : 0);
  if (total == 0) {
    final n = RegExp(r'\d+').firstMatch(rt);
    if (n != null) total = int.parse(n.group(0)!);
  }
  if (total == 0) return rt;
  if (total >= 60) return '${total ~/ 60}h ${(total % 60).toString().padLeft(2, '0')}m';
  return '${total}m';
}

String typeLabel(String t) => t == 'series' ? 'Series' : t == 'movie' ? 'Movie' : t;
