import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/mine/account/account_controller.dart';
import 'package:simple_live_app/modules/mine/parse/parse_controller.dart';
import 'package:simple_live_app/modules/search/search_list_controller.dart';
import 'package:simple_live_app/modules/search/search_list_view.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/widgets/douyin_room_entry_dialog.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _SearchController extends SearchListController {
  _SearchController() : super(Sites.allSites[Constant.kDouyin]!);
  int roomEntries = 0;
  int cookieSettings = 0;

  @override
  Future<void> enterDouyinRoom() async => roomEntries++;

  @override
  Future<void> configureDouyinCookie() async => cookieSettings++;

  @override
  Future<List> getData(int page, int pageSize) async => [];
}

class _AccountService extends DouyinAccountService {
  @override
  // ignore: must_call_super
  void onInit() {
    cookie = 'sessionid=fake; ttwid=test';
    hasCookie.value = true;
  }
}

class _NoSearchSite extends DouyinSite {
  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) {
    throw StateError('Direct room entry must not call keyword search');
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword, {int page = 1}) {
    throw StateError('Direct room entry must not call anchor search');
  }
}

void main() {
  tearDown(() => Get.reset());

  test(
    'cookie input accepts full headers without corrupting their first field',
    () {
      for (final input in [
        'sessionid=fake; ttwid=123; msToken=token==',
        'ttwid=123; sessionid=fake',
        '__ac_nonce=123; sessionid=fake',
      ]) {
        expect(DouyinAccountService.normalizeCookie(input), input);
      }
      expect(
        DouyinAccountService.normalizeCookie(
          ' Cookie: sessionid=fake; ttwid=123 ',
        ),
        'sessionid=fake; ttwid=123',
      );
      expect(
        DouyinAccountService.normalizeCookie(
          'cookie: sessionid=fake;\r\nttwid=123',
        ),
        'sessionid=fake; ttwid=123',
      );
      expect(
        DouyinAccountService.normalizeCookie(' 1%7Canonymous '),
        'ttwid=1%7Canonymous',
      );
      expect(DouyinAccountService.normalizeCookie('  '), '');
    },
  );

  testWidgets(
    'default ttwid can be restored without corrupting existing custom input',
    (tester) async {
      Get.put<DouyinAccountService>(_AccountService());
      await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
      AccountController().doDouyinCookieConfig();
      await tester.pumpAndSettle();
      expect(find.text('配置抖音 ttwid'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'sessionid=fake; ttwid=test');
      await tester.tap(find.text('恢复默认 ttwid'));
      await tester.pump();
      expect(field.controller!.text, '');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Douyin fallback stays reachable even with empty search results',
    (tester) async {
      final controller =
          Get.put<SearchListController>(
                _SearchController(),
                tag: Constant.kDouyin,
              )
              as _SearchController;
      await tester.pumpWidget(
        const GetMaterialApp(
          home: Scaffold(body: SearchListView(Constant.kDouyin)),
        ),
      );
      expect(find.text('房间号进入'), findsOneWidget);
      expect(find.text('ttwid 设置'), findsOneWidget);
      expect(find.textContaining('抖音号不等于直播房间号'), findsOneWidget);
      expect(find.text('网页搜索 / 登录'), findsNothing);

      await tester.tap(find.text('房间号进入'));
      await tester.tap(find.text('ttwid 设置'));
      expect(controller.roomEntries, 1);
      expect(controller.cookieSettings, 1);

      controller.searchMode.value = 1;
      await tester.pump();
      expect(find.text('房间号进入'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  for (final input in [
    ' 916628331770 ',
    'https://live.douyin.com/916628331770?from=share',
  ]) {
    testWidgets('direct entry navigates without search or login: $input', (
      tester,
    ) async {
      final site = Site(
        id: Constant.kDouyin,
        name: 'Douyin',
        logo: '',
        liveSite: _NoSearchSite(),
      );
      final controller = Get.put(SearchListController(site));
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: TextButton(
              onPressed: controller.enterDouyinRoom,
              child: const Text('open'),
            ),
          ),
          getPages: [
            GetPage(
              name: RoutePath.kLiveRoomDetail,
              page: () =>
                  Scaffold(body: Text('room:${Get.parameters['roomId']}')),
            ),
          ],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), input);
      await tester.tap(find.text('进入直播间'));
      await tester.pumpAndSettle();
      expect(find.text('room:916628331770'), findsOneWidget);
      expect(Get.arguments, same(site));
      expect(Get.isRegistered<DouyinAccountService>(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'invalid room input stays in dialog and cancel does not navigate',
    (tester) async {
      final controller = Get.put(
        SearchListController(Sites.allSites[Constant.kDouyin]!),
      );
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: TextButton(
              onPressed: controller.enterDouyinRoom,
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('进入直播间'));
      await tester.pumpAndSettle();
      expect(find.text('请输入直播房间号或完整链接'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'anchor name');
      await tester.tap(find.text('进入直播间'));
      await tester.pumpAndSettle();
      expect(find.text('请输入数字房间号或支持的抖音直播间链接'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(DouyinRoomEntryDialog), findsNothing);
      expect(Get.currentRoute, '/');
    },
  );

  testWidgets(
    'tools use the same room entry without parsing a search keyword',
    (tester) async {
      final controller = Get.put(ParseController());
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: TextButton(
              onPressed: controller.enterDouyinRoom,
              child: const Text('open'),
            ),
          ),
          getPages: [
            GetPage(
              name: RoutePath.kLiveRoomDetail,
              page: () =>
                  Scaffold(body: Text('room:${Get.parameters['roomId']}')),
            ),
          ],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '916628331770');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(find.text('room:916628331770'), findsOneWidget);
    },
  );

  testWidgets(
    'closing search while entry dialog is open prevents late navigation',
    (tester) async {
      final controller = Get.put(
        SearchListController(Sites.allSites[Constant.kDouyin]!),
      );
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: TextButton(
              onPressed: controller.enterDouyinRoom,
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      controller.onDelete();
      await tester.enterText(find.byType(TextFormField), '916628331770');
      await tester.tap(find.text('进入直播间'));
      await tester.pumpAndSettle();
      expect(Get.currentRoute, '/');
      expect(find.byType(DouyinRoomEntryDialog), findsNothing);
    },
  );
}
