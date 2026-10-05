import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';

class _Db extends DBService {
  final records = <FollowUser>[];
  final tags = <FollowUserTag>[];

  @override
  List<FollowUser> getFollowList() => records.toList();

  @override
  List<FollowUserTag> getFollowTagList() => tags.toList();
}

class _Follows extends FollowService {
  int statusUpdates = 0;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  void startUpdateStatus() => statusUpdates++;
}

class _DelayedPage extends FollowUserController {
  final result = Completer<List<FollowUser>>();

  @override
  Future<List<FollowUser>> getData(int page, int pageSize) => result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Db db;
  late _Follows follows;
  late FollowUserController controller;
  late FollowUser live;
  late FollowUser offline;

  FollowUser follow(String id, int status) => FollowUser(
    id: 'douyu_$id',
    roomId: id,
    siteId: 'douyu',
    userName: id,
    face: '',
    addTime: DateTime(2026),
  )..liveStatus.value = status;

  setUp(() async {
    db = _Db();
    live = follow('live', 2);
    offline = follow('offline', 1);
    db.records.addAll([live, offline]);
    Get.put<DBService>(db);
    follows = _Follows();
    Get.put<FollowService>(follows);
    await follows.loadData(updateStatus: false);
    controller = Get.put(FollowUserController());
  });

  tearDown(() async => Get.reset());

  test(
    'initial all list survives repeated live status notifications',
    () async {
      await controller.refreshData();
      for (var i = 0; i < 3; i++) {
        follows.filterData();
        await Future<void>.delayed(Duration.zero);
        expect(controller.list, [live, offline]);
        expect(follows.followList, [live, offline]);
        expect(controller.pageEmpty.value, isFalse);
      }
    },
  );

  test('refresh and filter switching preserve every service list', () async {
    await controller.refreshData();
    follows.filterData();
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 3; i++) {
      controller.setFilterMode(controller.tagList[1]);
      expect(controller.list, [live]);
      await controller.refreshData();
      follows.filterData();
      await Future<void>.delayed(Duration.zero);
      expect(controller.list, [live]);
      controller.setFilterMode(controller.tagList[2]);
      expect(controller.list, [offline]);
      await controller.refreshData();
      follows.filterData();
      await Future<void>.delayed(Duration.zero);
      expect(controller.list, [offline]);
      controller.setFilterMode(controller.tagList[0]);
      expect(controller.list, [live, offline]);
      expect(follows.followList, [live, offline]);
      expect(follows.liveList, [live]);
      expect(follows.notLiveList, [offline]);
    }
  });

  test(
    'custom tag remains populated after refresh and status updates',
    () async {
      final tag = FollowUserTag(
        id: 'favorites',
        tag: 'favorites',
        userId: [live.id, offline.id],
      );
      db.tags.add(tag);
      await controller.refreshData();
      controller.setFilterMode(tag);
      await controller.refreshData();
      follows.filterData();
      await Future<void>.delayed(Duration.zero);
      expect(controller.list, [live, offline]);
      expect(follows.curTagFollowList, [live, offline]);
      expect(tag.userId, [live.id, offline.id]);
      controller.setFilterMode(tag);
      expect(controller.list, [live, offline]);
    },
  );

  test(
    'database reload updates filters even without querying live status',
    () async {
      var notifications = 0;
      final subscription = follows.updatedListStream.listen(
        (_) => notifications++,
      );
      await follows.loadData(updateStatus: false);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
      expect(follows.liveList, [live]);
      expect(follows.notLiveList, [offline]);
      expect(follows.statusUpdates, 0);
      db.records.clear();
      await follows.loadData(updateStatus: false);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 2);
      expect(follows.followList, isEmpty);
      expect(follows.liveList, isEmpty);
      expect(follows.notLiveList, isEmpty);
      expect(controller.list, isEmpty);
      expect(controller.pageEmpty.value, isTrue);
      await subscription.cancel();
    },
  );

  test('refresh future waits until the page finishes loading', () async {
    final delayed = _DelayedPage();
    var completed = false;
    final refresh = delayed.refreshData().then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(delayed.loadding, isTrue);
    delayed.result.complete([live]);
    await refresh;
    expect(delayed.list, [live]);
    expect(delayed.loadding, isFalse);
    delayed.onDelete();
  });

  test('closed page ignores service notifications and refreshes', () async {
    await controller.refreshData();
    final updates = follows.statusUpdates;
    await Get.delete<FollowUserController>(force: true);
    follows.followList.clear();
    follows.filterData();
    await Future<void>.delayed(Duration.zero);
    expect(controller.list, [live, offline]);
    await controller.refreshData();
    expect(follows.statusUpdates, updates);
  });

  testWidgets(
    'empty overlay follows filters and disappears when data arrives',
    (tester) async {
      await controller.refreshData();
      controller.setFilterMode(
        FollowUserTag(id: 'empty', tag: 'empty', userId: []),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageGridView(
              pageController: controller,
              crossAxisCount: 1,
              itemBuilder: (_, index) => Text(controller.list[index].userName),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('这里什么都没有'), findsOneWidget);
      controller.setFilterMode(controller.tagList[0]);
      await tester.pump();
      expect(find.text('这里什么都没有'), findsNothing);
      expect(find.text('live'), findsOneWidget);
      db.records.clear();
      await follows.loadData(updateStatus: false);
      await tester.pump();
      await tester.pump();
      expect(find.text('这里什么都没有'), findsOneWidget);
      db.records.add(live);
      await follows.loadData(updateStatus: false);
      await tester.pump();
      await tester.pump();
      expect(find.text('这里什么都没有'), findsNothing);
      expect(find.text('live'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
