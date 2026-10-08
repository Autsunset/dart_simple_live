import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/mine/account/account_controller.dart';
import 'package:simple_live_app/modules/search/douyin/douyin_search_controller.dart';
import 'package:simple_live_app/modules/search/search_list_controller.dart';
import 'package:simple_live_app/modules/search/search_list_view.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';

class _SearchController extends SearchListController {
  _SearchController() : super(Sites.allSites[Constant.kDouyin]!);
  int webSearches = 0;
  int cookieSettings = 0;

  @override
  Future<void> openDouyinWebSearch() async => webSearches++;

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
    'existing full cookie can be edited without stripping its first key',
    (tester) async {
      Get.put<DouyinAccountService>(_AccountService());
      await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
      AccountController().doDouyinCookieConfig();
      await tester.pumpAndSettle();
      expect(find.text('配置抖音 Cookie'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'sessionid=fake; ttwid=test');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'web search opens the actual escaped keyword, including before view creation',
    () {
      final controller = DouyinSearchController(
        Sites.allSites[Constant.kDouyin]!,
        keyword: ' 主播 & #名字 ',
      );
      final uri = Uri.parse(controller.searchUrl);
      expect(uri.host, 'www.douyin.com');
      expect(uri.pathSegments.last, '主播 & #名字');
      expect(uri.queryParameters['type'], 'live');
      expect(uri.fragment, isEmpty);
      expect(
        controller.openRoom(Uri.parse('https://live.douyin.com/')),
        isFalse,
      );
      controller.onDelete();
      expect(
        controller.openRoom(Uri.parse('https://live.douyin.com/123456789012')),
        isFalse,
      );
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
      expect(find.text('网页搜索 / 登录'), findsOneWidget);
      expect(find.text('配置 Cookie'), findsOneWidget);
      expect(find.textContaining('抖音号不等于房间号'), findsOneWidget);

      await tester.tap(find.text('网页搜索 / 登录'));
      await tester.tap(find.text('配置 Cookie'));
      expect(controller.webSearches, 1);
      expect(controller.cookieSettings, 1);

      controller.searchMode.value = 1;
      await tester.pump();
      expect(find.textContaining('主播搜索仅返回'), findsOneWidget);
      expect(find.text('网页搜索 / 登录'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
