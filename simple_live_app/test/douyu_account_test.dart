import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/widgets/douyu_cookie_dialog.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _Box extends Fake implements Box<dynamic> {
  final entries = <dynamic, dynamic>{};
  bool failWrites = false;
  Completer<void>? writeGate;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      entries.containsKey(key) ? entries[key] : defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    await writeGate?.future;
    if (failWrites) throw StateError('storage unavailable');
    entries[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final site = Sites.allSites[Constant.kDouyu]!.liveSite as DouyuSite;
  late String originalCookie;
  late _Box box;
  late LocalStorageService storage;

  setUp(() {
    originalCookie = site.cookie;
    box = _Box();
    storage = Get.put(LocalStorageService()..settingsBox = box);
    Log.debugLogs.clear();
  });
  tearDown(() {
    site.cookie = originalCookie;
    Log.debugLogs.clear();
    Get.reset();
  });

  test('missing configuration remains anonymous, not a fake login', () {
    final account = Get.put(DouyuAccountService());
    expect(account.cookie, '');
    expect(account.hasCookie.value, isFalse);
    expect(site.cookie, '');
  });

  test('restores stored cookie and updates the shared playback site', () {
    box.entries[LocalStorageService.kDouyuCookie] =
        'Cookie: acf_did=account-device; acf_auth=private-session==';
    final account = Get.put(DouyuAccountService());
    expect(
      account.cookie,
      'acf_did=account-device; acf_auth=private-session==',
    );
    expect(site.cookie, account.cookie);
    expect(account.hasCookie.value, isTrue);
    expect(
      Log.debugLogs.any((e) => e.content.contains('private-session')),
      isFalse,
    );
  });

  test(
    'saving and clearing propagate to persistent storage and the core',
    () async {
      final account = Get.put(DouyuAccountService());
      await account.setCookie(
        ' Cookie: acf_did=mine;\r\nacf_auth=new-session==; ',
      );
      const expected = 'acf_did=mine; acf_auth=new-session==';
      expect(account.cookie, expected);
      expect(site.cookie, expected);
      expect(box.entries[LocalStorageService.kDouyuCookie], expected);
      await account.clearCookie();
      expect(account.cookie, '');
      expect(site.cookie, '');
      expect(account.hasCookie.value, isFalse);
      expect(box.entries[LocalStorageService.kDouyuCookie], '');
    },
  );

  test('configuration takes effect only after the write succeeds', () async {
    final account = Get.put(DouyuAccountService());
    await account.setCookie('acf_did=old; acf_auth=old-session');
    box.writeGate = Completer<void>();
    final saving = account.setCookie('acf_did=new; acf_auth=new-session');
    expect(site.cookie, 'acf_did=old; acf_auth=old-session');
    box.writeGate!.complete();
    await saving;
    expect(site.cookie, 'acf_did=new; acf_auth=new-session');
    box.failWrites = true;
    await expectLater(account.clearCookie(), throwsStateError);
    expect(account.hasCookie.value, isTrue);
    expect(site.cookie, 'acf_did=new; acf_auth=new-session');
  });

  test('malformed cookies do not replace a working configuration', () async {
    final account = Get.put(DouyuAccountService());
    await account.setCookie('acf_did=mine; acf_auth=working');
    for (final input in [
      'https://www.douyu.com/6657',
      'raw-device-id',
      'acf_auth=session-only',
      'acf_did=; acf_auth=empty-device',
      'bad name=value; acf_did=mine',
    ]) {
      await expectLater(account.setCookie(input), throwsArgumentError);
      expect(site.cookie, 'acf_did=mine; acf_auth=working');
    }
  });

  test('all platform cookie values are redacted from storage logs', () async {
    for (final key in [
      LocalStorageService.kBilibiliCookie,
      LocalStorageService.kDouyinCookie,
      LocalStorageService.kDouyuCookie,
    ]) {
      await storage.setValue(key, 'private-login-value');
      expect(storage.getValue(key, ''), 'private-login-value');
    }
    expect(
      Log.debugLogs.where((e) => e.content.contains('[redacted]')),
      hasLength(6),
    );
    expect(
      Log.debugLogs.any((e) => e.content.contains('private-login-value')),
      isFalse,
    );
  });

  testWidgets('cookie dialog validates input and returns an intact cookie', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Get.dialog<String>(
                const DouyuCookieDialog(initialValue: ''),
              );
            },
            child: const Text('configure'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('configure'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'acf_auth=incomplete');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cookie 缺少 acf_did'), findsOneWidget);
    expect(result, isNull);
    await tester.enterText(
      find.byType(TextFormField),
      'Cookie: acf_did=mine; acf_auth=session==',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, 'acf_did=mine; acf_auth=session==');
  });

  testWidgets('clearing and saving explicitly returns anonymous mode', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Get.dialog<String>(
                const DouyuCookieDialog(
                  initialValue: 'acf_did=mine; acf_auth=existing',
                ),
              );
            },
            child: const Text('configure'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('configure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除 Cookie，恢复匿名'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, '');
  });
}
