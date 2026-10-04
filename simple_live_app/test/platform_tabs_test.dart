import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/indexed/indexed_controller.dart';
import 'package:simple_live_app/modules/home/home_controller.dart';
import 'package:simple_live_app/modules/category/category_controller.dart';

class _Settings extends AppSettingsController {
  @override
  // ignore: must_call_super
  void onInit() {
    siteSort.assignAll(['bilibili', 'douyu', 'huya', 'douyin']);
    homeSort.assignAll(['recommend', 'follow', 'category', 'user']);
  }
}

void main() {
  testWidgets(
    'home and category retain the same selected platform on tap and swipe',
    (tester) async {
      Get.put<AppSettingsController>(_Settings());
      final indexed = Get.put(IndexedController());
      final home = Get.find<HomeController>();
      final category = Get.put(CategoryController());
      expect(identical(home.tabController, category.tabController), isTrue);
      Widget view(TabController tabs, String prefix) => TabBarView(
        controller: tabs,
        children: List.generate(4, (i) => Center(child: Text('$prefix$i'))),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TabBar(
                  controller: home.tabController,
                  tabs: List.generate(4, (i) => Tab(text: 'platform$i')),
                ),
                Expanded(child: view(home.tabController, 'home')),
                Expanded(child: view(category.tabController, 'category')),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('platform2'));
      await tester.pumpAndSettle();
      expect(indexed.tabController.index, 2);
      expect(find.text('home2').hitTestable(), findsOneWidget);
      expect(find.text('category2').hitTestable(), findsOneWidget);
      await tester.drag(find.byType(TabBarView).last, const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(indexed.tabController.index, 3);
      expect(find.text('home3').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      Get.reset();
      expect(tester.takeException(), isNull);
    },
  );
}
