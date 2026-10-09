import 'dart:convert';

/// Accepts request headers and Netscape cookie files without decoding values.
class CookieInput {
  static const maxLength = 2 * 1024 * 1024;
  static const _httpOnlyPrefix = '#HttpOnly_';
  static final _namePattern = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
  static final _controlPattern = RegExp(r'[\x00-\x1f\x7f]');

  static String _text(String input) {
    if (input.length > maxLength) {
      throw const FormatException('Cookie 内容过大，请只导出当前平台的 Cookie');
    }
    return input.startsWith('\uFEFF') ? input.substring(1) : input;
  }

  static bool isNetscape(String input) {
    final text = _text(input);
    final start = text.trimLeft();
    if (start.startsWith('#')) return true;
    if (RegExp(r'^cookie:', caseSensitive: false).hasMatch(start)) return false;
    return const LineSplitter().convert(text).any((line) {
      final trimmed = line.trimLeft();
      final tab = trimmed.indexOf('\t');
      return (tab >= 0 && !trimmed.substring(0, tab).contains('=')) ||
          RegExp(
            r'^\.?[a-z0-9.-]+\s+(TRUE|FALSE)\s+/',
            caseSensitive: false,
          ).hasMatch(trimmed);
    });
  }

  /// Preserve file attributes in storage so later requests can enforce them.
  static String normalizeForStorage(
    String input, {
    required String domain,
    DateTime? now,
  }) {
    final text = _text(input);
    if (!isNetscape(text)) return _header(text);
    final entries = _file(text, baseDomain: domain);
    if (entries.isEmpty) {
      throw FormatException('文件中没有 $domain 的 Cookie，请确认选择了正确平台');
    }
    final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final active = entries.where((entry) => entry.isActive(timestamp)).toList();
    if (active.isEmpty) {
      throw const FormatException('该平台的 Cookie 均已过期，请重新导出');
    }
    return '# Netscape HTTP Cookie File\n'
        '${active.map((entry) => entry.toLine()).join('\n')}\n';
  }

  static String headerFor(String input, Uri url, {DateTime? now}) {
    final text = _text(input);
    if (!isNetscape(text)) return _header(text);
    final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final entries =
        _file(text)
            .where((entry) => entry.isActive(timestamp) && entry.matches(url))
            .toList()
          ..sort((a, b) {
            final pathOrder = b.path.length.compareTo(a.path.length);
            return pathOrder != 0 ? pathOrder : a.order.compareTo(b.order);
          });
    return entries.map((entry) => '${entry.name}=${entry.value}').join('; ');
  }

  static String _header(String input) {
    final text = input
        .trim()
        .replaceFirst(RegExp(r'^cookie:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ');
    final pairs = <String>[];
    for (final part in text.split(';')) {
      final pair = part.trim();
      if (pair.isEmpty) continue;
      final separator = pair.indexOf('=');
      if (separator <= 0) {
        throw const FormatException('请输入 name=value 格式或 Netscape Cookie 文件');
      }
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1);
      _validatePair(name, value);
      pairs.add('$name=$value');
    }
    return pairs.join('; ');
  }

  static void _validatePair(String name, String value) {
    if (!_namePattern.hasMatch(name) ||
        _controlPattern.hasMatch(value) ||
        value.contains(';')) {
      // Never attach the input/source to exceptions: it contains credentials.
      throw const FormatException('Cookie 名称或值包含不支持的字符');
    }
  }

  static List<_CookieEntry> _file(String input, {String? baseDomain}) {
    final entries = <String, _CookieEntry>{};
    final lines = const LineSplitter().convert(input);
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trimLeft();
      final httpOnly = line.startsWith(_httpOnlyPrefix);
      if (httpOnly) line = line.substring(_httpOnlyPrefix.length);
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final parts = line.split('\t');
      if (parts.length != 7) {
        throw FormatException('Cookie 文件第 ${i + 1} 行不是七列 Tab 分隔格式');
      }
      final storedDomain = parts[0].trim().toLowerCase();
      final domain = storedDomain.startsWith('.')
          ? storedDomain.substring(1)
          : storedDomain;
      if (baseDomain != null &&
          domain != baseDomain &&
          !domain.endsWith('.$baseDomain')) {
        continue;
      }
      final subdomains = parts[1].trim().toUpperCase();
      final secure = parts[3].trim().toUpperCase();
      final expires = int.tryParse(parts[4].trim());
      final path = parts[2];
      if (domain.isEmpty ||
          !RegExp(r'^[a-z0-9.-]+$').hasMatch(domain) ||
          domain.split('.').any((label) => label.isEmpty) ||
          !['TRUE', 'FALSE'].contains(subdomains) ||
          !['TRUE', 'FALSE'].contains(secure) ||
          expires == null ||
          !path.startsWith('/') ||
          _controlPattern.hasMatch(path)) {
        throw FormatException('Cookie 文件第 ${i + 1} 行的属性无效');
      }
      final name = parts[5].trim();
      final value = parts[6];
      _validatePair(name, value);
      final entry = _CookieEntry(
        storedDomain,
        domain,
        subdomains == 'TRUE',
        path,
        secure == 'TRUE',
        expires,
        name,
        value,
        httpOnly,
        i,
      );
      // Replace only the same scope, not host/path variants of the same name.
      final scope = '$domain\t$subdomains\t$path\t$name';
      entries.remove(scope);
      entries[scope] = entry;
    }
    return entries.values.toList();
  }
}

class _CookieEntry {
  final String storedDomain, domain, path, name, value;
  final bool subdomains, secure, httpOnly;
  final int expires, order;

  _CookieEntry(
    this.storedDomain,
    this.domain,
    this.subdomains,
    this.path,
    this.secure,
    this.expires,
    this.name,
    this.value,
    this.httpOnly,
    this.order,
  );

  bool isActive(int timestamp) => expires == 0 || expires > timestamp;

  bool matches(Uri url) {
    if (!['http', 'https', 'ws', 'wss'].contains(url.scheme)) return false;
    if (secure && url.scheme != 'https' && url.scheme != 'wss') return false;
    final host = url.host.toLowerCase();
    if (host != domain && !(subdomains && host.endsWith('.$domain'))) {
      return false;
    }
    final requestPath = url.path.isEmpty ? '/' : url.path;
    return requestPath == path ||
        (requestPath.startsWith(path) &&
            (path.endsWith('/') ||
                (requestPath.length > path.length &&
                    requestPath[path.length] == '/')));
  }

  String toLine() => [
    '${httpOnly ? CookieInput._httpOnlyPrefix : ''}$storedDomain',
    subdomains ? 'TRUE' : 'FALSE',
    path,
    secure ? 'TRUE' : 'FALSE',
    expires.toString(),
    name,
    value,
  ].join('\t');
}
