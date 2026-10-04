import 'dart:convert';

/// Reads an array from Next.js/Pace flight strings without assuming it is the last
/// field in a record. Decode the outer string before scanning nested arrays.
List<dynamic> extractNextDataArray(String html, String key) {
  final sources = <String>[html];
  final chunks = RegExp(
    r'self\.__\w+_f\.push\(\[\d+,\s*("(?:\\.|[^"\\])*")\]\)',
  );
  for (final match in chunks.allMatches(html)) {
    sources.add(jsonDecode(match.group(1)!) as String);
  }
  final marker = RegExp('"${RegExp.escape(key)}"\\s*:\\s*\\[');
  for (final source in sources) {
    for (final match in marker.allMatches(source)) {
      final start = source.indexOf('[', match.start);
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var i = start; i < source.length; i++) {
        final char = source[i];
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (char == '\\') {
            escaped = true;
          } else if (char == '"') {
            inString = false;
          }
          continue;
        }
        if (char == '"') {
          inString = true;
        } else if (char == '[') {
          depth++;
        } else if (char == ']' && --depth == 0) {
          return jsonDecode(source.substring(start, i + 1)) as List<dynamic>;
        }
      }
    }
  }
  throw FormatException('缺少有效的 $key 数据');
}
