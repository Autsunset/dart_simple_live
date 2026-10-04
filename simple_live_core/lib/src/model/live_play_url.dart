import 'dart:convert';

class LivePlayUrl {
  /// 播放地址
  final List<String> urls;

  /// 请求头
  final Map<String, String>? headers;

  /// Actual server-returned quality per URL, when reported by the platform.
  /// Entries correspond to [urls]; null/empty entries retain the requested name.
  final List<String>? qualities;

  LivePlayUrl({required this.urls, this.headers, this.qualities});

  @override
  String toString() {
    return json.encode({
      "urls": urls,
      "headers": headers.toString(),
      "qualities": qualities,
    });
  }
}
