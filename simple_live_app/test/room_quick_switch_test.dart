import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_page.dart';
import 'package:simple_live_app/modules/live_room/widgets/room_quick_switch.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';

class _Settings extends AppSettingsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Db extends DBService {
  final records = <History>[];
  int reads = 0;
  @override
  List<History> getHistores() {
    reads++;
    return records;
  }
}

class _Follows extends FollowService {
  int refreshes = 0;
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  Future<void> loadData({bool updateStatus = true}) async => refreshes++;
}

class _Player extends Fake implements Player {
  @override
  Future<void> dispose() async {}
}

class _Room extends LiveRoomController {
  _Room() : super(pSite: Sites.allSites['bilibili']!, pRoomId: '1');
  final selections = <(String, String)>[];
  final _testPlayer = _Player();
  @override
  _Player get player => _testPlayer;
  @override
  Future<void> resetSystem() async {}
  @override
  void resetRoom(Site site, String roomId) => selections.add((site.id, roomId));
}

class _MessageRoom extends _Room {
  @override
  // ignore: must_call_super
  void onInit() {}
}

void main() {
  late _Db db;
  late _Follows follows;
  late _Room room;
  var closes = 0;
  History history(String id, String site, String name) => History(
    id: '${site}_$id',
    roomId: id,
    siteId: site,
    userName: name,
    face: '',
    updateTime: DateTime.now(),
  );
  Widget picker() => MaterialApp(
    home: Scaffold(
      body: RoomQuickSwitch(controller: room, close: () => closes++),
    ),
  );
  setUp(() {
    Get.put<AppSettingsController>(_Settings());
    db = _Db();
    follows = _Follows();
    Get.put<DBService>(db);
    Get.put<FollowService>(follows);
    room = _Room();
    closes = 0;
  });
  tearDown(() => Get.reset());

  testWidgets('history tab remembers selection and switches the current room', (
    tester,
  ) async {
    db.records.addAll([
      history('1', 'bilibili', 'current'),
      history('2', 'douyu', 'another'),
      history('3', 'removed-platform', 'unsupported'),
    ]);
    await tester.pumpWidget(picker());
    await tester.tap(find.text('观看历史'));
    await tester.pumpAndSettle();
    expect(room.quickSwitchTab.value, 1);
    expect(find.text('unsupported'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(db.reads, 1);
    await tester.tap(find.text('another'));
    expect(closes, 1);
    expect(room.selections, [('douyu', '2')]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(picker());
    await tester.pumpAndSettle();
    expect(find.text('another').hitTestable(), findsOneWidget);
    expect(db.reads, 2);
    await tester.pumpWidget(const SizedBox());
    room.onClose();
    await tester.pump();
  });

  testWidgets(
    'empty follows can refresh and live updates do not reload history',
    (tester) async {
      await tester.pumpWidget(picker());
      expect(find.text('暂无正在直播的关注'), findsOneWidget);
      await tester.timedDrag(
        find.byType(ListView).first,
        const Offset(0, 400),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      expect(follows.refreshes, 1);
      follows.liveList.add(
        FollowUser(
          id: 'douyu_2',
          roomId: '2',
          siteId: 'douyu',
          userName: 'live follow',
          face: '',
          addTime: DateTime.now(),
        ),
      );
      await tester.pump();
      expect(find.textContaining('live follow'), findsOneWidget);
      expect(db.reads, 1);
      await tester.tap(find.textContaining('live follow'));
      expect(room.selections, [('douyu', '2')]);
      await tester.pumpWidget(const SizedBox());
      room.onClose();
      await tester.pump();
    },
  );

  testWidgets('empty history and callbacks after room close are harmless', (
    tester,
  ) async {
    room.quickSwitchTab.value = 1;
    await tester.pumpWidget(picker());
    expect(find.text('暂无观看历史'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    db.records.add(history('2', 'douyu', 'another'));
    await tester.pumpWidget(picker());
    room.onClose();
    await tester.tap(find.text('another'));
    expect(closes, 0);
    expect(room.selections, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('message tabs reset when changing to a platform without SC', (
    tester,
  ) async {
    room = _MessageRoom();
    Get.put<LiveRoomController>(room);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(children: [const LiveRoomPage().buildMessageArea()]),
        ),
      ),
    );
    expect(find.text('SC'), findsOneWidget);
    await tester.tap(find.text('SC'));
    await tester.pumpAndSettle();
    room.rxSite.value = Sites.allSites['douyu']!;
    await tester.pumpAndSettle();
    expect(find.text('SC'), findsNothing);
    expect(tester.widget<TabBar>(find.byType(TabBar)).tabs.length, 3);
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBar))).index,
      0,
    );
    room.rxSite.value = Sites.allSites['bilibili']!;
    await tester.pumpAndSettle();
    expect(find.text('SC'), findsOneWidget);
    expect(tester.widget<TabBar>(find.byType(TabBar)).tabs.length, 4);
    await tester.pumpWidget(const SizedBox());
    Get.delete<LiveRoomController>();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
