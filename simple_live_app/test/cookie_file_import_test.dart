import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/utils/cookie_file.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/widgets/cookie_file_import_button.dart';
import 'package:simple_live_app/widgets/douyin_cookie_dialog.dart';
import 'package:simple_live_app/widgets/douyu_cookie_dialog.dart';
import 'package:simple_live_core/simple_live_core.dart';

const _douyu =
    '# Netscape HTTP Cookie File\n'
    '.douyu.com\tTRUE\t/\tFALSE\t0\tdy_did\tdevice\n'
    'www.douyu.com\tFALSE\t/\tFALSE\t0\tacf_did\tdevice\n'
    '#HttpOnly_www.douyu.com\tFALSE\t/\tTRUE\t0\tacf_auth\ttoken%2F+==\n'
    '.douyin.com\tTRUE\t/\tTRUE\t0\tsessionid\tother-platform\n';
const _douyin =
    '# Netscape HTTP Cookie File\n'
    '.douyin.com\tTRUE\t/\tTRUE\t0\tttwid\t1%7Cfake\n'
    '#HttpOnly_.douyin.com\tTRUE\t/\tTRUE\t0\tsessionid\ttoken%2B+==\n'
    'live.douyin.com\tFALSE\t/\tTRUE\t0\tfpk1\tlive-only\n';

class _Picker extends FilePicker {
  FilePickerResult? result;
  Completer<FilePickerResult?>? gate;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(withData, isFalse);
    expect(withReadStream, isTrue);
    expect(allowedExtensions, ['txt']);
    return gate == null ? result : gate!.future;
  }
}

PlatformFile _file(String text) => PlatformFile(
  name: 'cookies.txt',
  size: utf8.encode(text).length,
  readStream: Stream.value(utf8.encode(text)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FilePicker? original;
  late _Picker picker;
  setUp(() {
    try {
      original = FilePicker.platform;
    } catch (_) {}
    picker = _Picker();
    FilePicker.platform = picker;
  });
  tearDown(() {
    if (original != null) FilePicker.platform = original!;
    Get.reset();
  });

  test('reader handles streams, bytes and native path fallback', () async {
    expect(await CookieFile.readText(_file(_douyu)), _douyu);
    expect(
      await CookieFile.readText(
        PlatformFile(
          name: 'cookies.txt',
          size: 0,
          bytes: Uint8List.fromList(utf8.encode(_douyin)),
        ),
      ),
      _douyin,
    );
    final directory = await Directory.systemTemp.createTemp(
      'cookie-format-test-',
    );
    try {
      final file = await File(
        '${directory.path}/cookies.txt',
      ).writeAsString(_douyu);
      expect(
        await CookieFile.readText(
          PlatformFile(name: 'cookies.txt', size: 0, path: file.path),
        ),
        _douyu,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('reader rejects empty, oversized and invalid UTF-8 files', () async {
    for (final file in [
      _file(''),
      PlatformFile(name: 'cookies.txt', size: CookieFile.maxBytes + 1),
      PlatformFile(
        name: 'cookies.txt',
        size: 0,
        readStream: Stream.value(List.filled(CookieFile.maxBytes + 1, 65)),
      ),
      PlatformFile(
        name: 'cookies.txt',
        size: 2,
        bytes: Uint8List.fromList([0xff, 0xff]),
      ),
      PlatformFile(name: 'cookies.txt', size: 0),
    ]) {
      await expectLater(
        CookieFile.readText(file),
        throwsA(isA<CookieFileException>()),
      );
    }
  });

  test('normalization filters other platforms but retains file attributes', () {
    final saved = DouyuAccountService.normalizeCookie(_douyu);
    expect(saved, startsWith('# Netscape HTTP Cookie File'));
    expect(saved, contains('#HttpOnly_www.douyu.com'));
    expect(saved, isNot(contains('other-platform')));
    expect(DouyuAccountService.validateCookie(saved), isNull);
    expect(
      CookieInput.headerFor(
        saved,
        Uri.parse('https://www.douyu.com/lapi/live/getH5Play/1'),
      ),
      'dy_did=device; acf_did=device; acf_auth=token%2F+==',
    );
    final dySaved = DouyinAccountService.normalizeCookie(_douyin);
    expect(
      CookieInput.headerFor(dySaved, Uri.parse('https://live.douyin.com/')),
      'ttwid=1%7Cfake; sessionid=token%2B+==; fpk1=live-only',
    );
    expect(
      CookieInput.headerFor(dySaved, Uri.parse('https://www.douyin.com/')),
      'ttwid=1%7Cfake; sessionid=token%2B+==',
    );
  });

  test(
    'validators reject wrong-platform files and malformed data without echoing values',
    () {
      expect(
        DouyuAccountService.validateCookie(_douyin),
        contains('douyu.com'),
      );
      expect(
        DouyinAccountService.validateCookie(
          'www.douyu.com\tFALSE\t/\tFALSE\t0\tacf_did\tprivate-secret',
        ),
        contains('douyin.com'),
      );
      expect(
        DouyuAccountService.validateCookie(
          '# Netscape HTTP Cookie File\nwww.douyu.com\tFALSE\t/\tFALSE\t0\tacf_auth\tprivate-secret\tbad-column',
        ),
        isNot(contains('private-secret')),
      );
    },
  );

  testWidgets('Douyu dialog accepts the pasted seven-column export', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: TextButton(
            onPressed: () async {
              saved = await Get.dialog<String>(
                const DouyuCookieDialog(initialValue: ''),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), _douyu);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, DouyuAccountService.normalizeCookie(_douyu));
  });

  testWidgets(
    'Douyin file picker imports valid data and rejects a Douyu file',
    (tester) async {
      String? saved;
      picker.result = FilePickerResult([_file(_douyin)]);
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await Get.dialog<String>(
                  const DouyinCookieDialog(initialValue: 'ttwid=old'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('导入 cookies.txt'));
      await tester.tap(find.text('导入 cookies.txt'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        _douyin,
      );
      picker.result = FilePickerResult([
        _file('www.douyu.com\tFALSE\t/\tFALSE\t0\tacf_did\twrong'),
      ]);
      await tester.tap(find.text('导入 cookies.txt'));
      await tester.pumpAndSettle();
      expect(find.textContaining('文件中没有 douyin.com'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        _douyin,
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(saved, DouyinAccountService.normalizeCookie(_douyin));
    },
  );

  testWidgets(
    'cancelled and empty file selection preserve the previous input',
    (tester) async {
      final input = TextEditingController(text: 'acf_did=old; acf_auth=old');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CookieFileImportButton(
              controller: input,
              validate: DouyuAccountService.validateCookie,
              normalize: DouyuAccountService.normalizeCookie,
            ),
          ),
        ),
      );
      await tester.tap(find.text('导入 cookies.txt'));
      await tester.pumpAndSettle();
      expect(input.text, 'acf_did=old; acf_auth=old');
      picker.result = FilePickerResult([_file('')]);
      await tester.tap(find.text('导入 cookies.txt'));
      await tester.pumpAndSettle();
      expect(find.text('Cookie 文件为空'), findsOneWidget);
      expect(input.text, 'acf_did=old; acf_auth=old');
      await tester.pumpWidget(const SizedBox());
      input.dispose();
    },
  );

  testWidgets('late picker completion cannot update a disposed editor', (
    tester,
  ) async {
    final input = TextEditingController(text: 'acf_did=old');
    picker.gate = Completer<FilePickerResult?>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CookieFileImportButton(
            controller: input,
            validate: DouyuAccountService.validateCookie,
            normalize: DouyuAccountService.normalizeCookie,
          ),
        ),
      ),
    );
    await tester.tap(find.text('导入 cookies.txt'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    input.dispose();
    picker.gate!.complete(FilePickerResult([_file(_douyu)]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
