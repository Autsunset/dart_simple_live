import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class CookieFileException implements Exception {
  final String message;
  const CookieFileException(this.message);
}

class CookieFile {
  static const maxBytes = 2 * 1024 * 1024;

  static Future<String?> pickText() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入 Cookie 文件',
      type: FileType.custom,
      allowedExtensions: ['txt'],
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return readText(result.files.single);
  }

  static Future<String> readText(PlatformFile file) async {
    if (file.size > maxBytes) {
      throw const CookieFileException('Cookie 文件不能超过 2 MiB，请只导出当前平台');
    }
    final stream =
        file.readStream ??
        (file.bytes != null
            ? Stream<List<int>>.value(file.bytes!)
            : file.path != null
            ? File(file.path!).openRead()
            : null);
    if (stream == null) throw const CookieFileException('无法读取所选 Cookie 文件');
    final data = BytesBuilder();
    await for (final bytes in stream) {
      if (data.length + bytes.length > maxBytes) {
        throw const CookieFileException('Cookie 文件不能超过 2 MiB，请只导出当前平台');
      }
      data.add(bytes);
    }
    String text;
    try {
      text = utf8.decode(data.takeBytes());
    } on FormatException {
      throw const CookieFileException('文件不是 UTF-8 文本，请重新导出 cookies.txt');
    }
    if (text.trim().isEmpty) throw const CookieFileException('Cookie 文件为空');
    return text;
  }
}
