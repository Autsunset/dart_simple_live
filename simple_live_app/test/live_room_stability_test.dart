import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_controls.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _Settings extends AppSettingsController {
  // Tests do not initialize persistent application settings.
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Player extends Fake implements Player {
  final jumps = <int>[];
  int disposed = 0;
  @override
  Future<void> stop() async {}

  @override
  Future<void> open(Playable playable, {bool play = true}) async {}

  @override
  Future<void> jump(int index) async => jumps.add(index);

  @override
  Future<void> dispose() async => disposed++;
}

class _Room extends LiveRoomController {
  _Room()
    : super(
        pSite: Site(id: 'douyu', liveSite: DouyuSite(), logo: '', name: '斗鱼'),
        pRoomId: '1',
      );

  final testPlayer = _Player();
  final autoExitAnswer = Completer<bool>();
  var exitCalls = 0;
  var delaySheetCalls = 0;
  @override
  Future<bool> showAutoExitConfirmation() => autoExitAnswer.future;
  @override
  void exitApplication() => exitCalls++;
  @override
  void showAutoExitSheet() => delaySheetCalls++;

  @override
  _Player get player => testPlayer;

  @override
  Future<void> initializePlayer() async {}

  @override
  Future<void> resetSystem() async {}
}

class _SwitchRoom extends _Room {
  var loads = 0;
  @override
  void loadData() => loads++;
}

class _PlaySite extends Fake implements LiveSite {
  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrl(
    urls: ['https://example.invalid/low', 'https://example.invalid/original'],
    qualities: ['高清', '原画1080P60'],
  );
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.put<AppSettingsController>(_Settings());
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
  });
  tearDown(() => Get.reset());

  testWidgets(
    'chat history remains bounded even while automatic scrolling is disabled',
    (tester) async {
      final room = _Room()..isBackground = true;
      room.disableAutoScroll.value = true;
      for (var i = 0; i < 5000; i++) {
        room.onWSMessage(
          LiveMessage(
            type: LiveMessageType.chat,
            userName: 'user',
            message: '$i',
            color: LiveMessageColor.white,
          ),
        );
      }
      await tester.pump(LiveRoomController.chatFlushInterval);
      expect(room.messages.length, LiveRoomController.maxChatMessages);
      expect(room.messages.last.message, '4999');
      room.onClose();
    },
  );

  test(
    'system messages and late callbacks cannot grow a closed room',
    () async {
      final room = _Room();
      for (var i = 0; i < 1000; i++) {
        room.addSysMsg('$i');
      }
      expect(room.messages.length, 200);
      room.onClose();
      room.addSysMsg('late');
      room.onWSMessage(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: '',
          message: 'late',
          color: LiveMessageColor.white,
        ),
      );
      expect(room.messages.length, 200);
      await Future<void>.delayed(Duration.zero);
      expect(room.player.disposed, 1);
    },
  );

  testWidgets('error and completed bursts produce only one delayed retry', (
    tester,
  ) async {
    final room = _Room();
    room.playUrls.addAll([
      'https://example.invalid/first',
      'https://example.invalid/second',
    ]);
    room.currentLineIndex = 0;
    await room.initPlaylist(0, 0);
    for (var i = 0; i < 20; i++) {
      room.mediaError('network');
      room.mediaEnd();
    }
    await tester.pump(const Duration(milliseconds: 999));
    expect(room.player.jumps, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(room.player.jumps, [0]);
    expect(room.mediaErrorRetryCount, 1);
    room.mediaError('network');
    room.onClose();
    await tester.pump(const Duration(seconds: 2));
    expect(room.player.jumps, [0]);
    expect(room.player.disposed, 1);
  });

  testWidgets('manually changing line cancels the pending failure retry', (
    tester,
  ) async {
    final room = _Room();
    room.playUrls.addAll([
      'https://example.invalid/first',
      'https://example.invalid/second',
    ]);
    room.currentLineIndex = 0;
    await room.initPlaylist(0, 0);
    room.mediaError('network');
    room.changePlayLine(1);
    await tester.pump(const Duration(seconds: 2));
    expect(room.player.jumps, [1]);
    expect(room.mediaErrorRetryCount, 0);
    room.onClose();
    await tester.pump();
  });
  testWidgets('a burst publishes once, filters messages and drops late work', (
    tester,
  ) async {
    final room = _Room()..isBackground = true;
    final settings = AppSettingsController.instance;
    settings.shieldList.addAll(['blocked', '/^spam/']);
    var publications = 0;
    final worker = ever(room.messages, (_) => publications++);
    for (var i = 0; i < 1000; i++) {
      room.onWSMessage(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: 'user',
          message: '$i',
          color: LiveMessageColor.white,
        ),
      );
    }
    for (final text in ['blocked text', 'spam text']) {
      room.onWSMessage(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: 'user',
          message: text,
          color: LiveMessageColor.white,
        ),
      );
    }
    expect(room.messages, isEmpty);
    await tester.pump(LiveRoomController.chatFlushInterval);
    expect(publications, 1);
    expect(room.messages.length, 200);
    expect(room.messages.first.message, '800');
    expect(room.messages.last.message, '999');
    room.onWSMessage(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: '',
        message: 'late',
        color: LiveMessageColor.white,
      ),
    );
    room.onClose();
    await tester.pump(const Duration(seconds: 1));
    expect(publications, 1);
    worker.dispose();
  });

  testWidgets('scrolling back to the bottom restores message following', (
    tester,
  ) async {
    final room = _Room();
    room.scrollController.addListener(room.scrollListener);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: room.scrollController,
            itemCount: 100,
            itemExtent: 50,
            itemBuilder: (_, i) => Text('$i'),
          ),
        ),
      ),
    );
    room.scrollController.jumpTo(
      room.scrollController.position.maxScrollExtent,
    );
    await tester.drag(find.byType(ListView), const Offset(0, 250));
    await tester.pumpAndSettle();
    expect(room.disableAutoScroll.value, isTrue);
    room.scrollController.jumpTo(
      room.scrollController.position.maxScrollExtent,
    );
    expect(room.disableAutoScroll.value, isFalse);
    await tester.pumpWidget(const SizedBox());
    room.onClose();
    await tester.pump();
  });

  test('SC snapshots merge with websocket updates by stable identity', () {
    final room = _Room();
    final now = DateTime.now();
    LiveSuperChatMessage sc(String id, String text, DateTime end) =>
        LiveSuperChatMessage(
          id: id,
          userName: 'user',
          face: '',
          message: text,
          price: 30,
          startTime: now,
          endTime: end,
          backgroundColor: '#ffffff',
          backgroundBottomColor: '#ffffff',
        );
    void send(LiveSuperChatMessage message) => room.onWSMessage(
      LiveMessage(
        type: LiveMessageType.superChat,
        userName: '',
        message: '',
        data: message,
        color: LiveMessageColor.white,
      ),
    );
    send(sc('1', 'first', now.add(const Duration(minutes: 1))));
    send(sc('1', 'updated', now.add(const Duration(minutes: 2))));
    send(sc('2', 'expired', now.subtract(const Duration(seconds: 1))));
    expect(room.superChats.length, 1);
    expect(room.superChats.single.message, 'updated');
    room.onClose();
  });
  testWidgets('SC overlay expires once and does not replay on another update', (
    tester,
  ) async {
    final room = _Room();
    final now = DateTime.now();
    LiveSuperChatMessage sc(String id, String text) => LiveSuperChatMessage(
      id: id,
      userName: 'user',
      face: '',
      message: text,
      price: 30,
      startTime: now,
      endTime: now.add(const Duration(minutes: 2)),
      backgroundColor: '#ffffff',
      backgroundBottomColor: '#ffffff',
    );
    room.superChats.add(sc('1', 'first SC'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlayerSuperChatOverlay(controller: room)),
      ),
    );
    expect(find.text('first SC'), findsOneWidget);
    await tester.pump(const Duration(seconds: 16));
    expect(find.text('first SC'), findsNothing);
    room.superChats.add(sc('2', 'second SC'));
    await tester.pump();
    expect(find.text('first SC'), findsNothing);
    expect(find.text('second SC'), findsOneWidget);
    room.superChats[1] = sc('2', 'updated SC');
    await tester.pump();
    expect(find.text('updated SC'), findsOneWidget);
    room.superChats.clear();
    await tester.pump();
    expect(find.text('updated SC'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    room.onClose();
    await tester.pump();
  });
  testWidgets('closing a room cancels the auto-exit confirmation timeout', (
    tester,
  ) async {
    final room = _Room()
      ..autoExitEnable.value = true
      ..autoExitMinutes.value = 0;
    room.setAutoExit();
    await tester.pump(const Duration(seconds: 1));
    room.onClose();
    await tester.pump(const Duration(seconds: 12));
    room.autoExitAnswer.complete(false);
    await tester.pump();
    expect(room.exitCalls, 0);
  });
  testWidgets('disabling auto-exit invalidates a pending dialog result', (
    tester,
  ) async {
    final room = _Room()
      ..autoExitEnable.value = true
      ..autoExitMinutes.value = 0;
    room.setAutoExit();
    await tester.pump(const Duration(seconds: 1));
    room.autoExitEnable.value = false;
    room.setAutoExit();
    room.autoExitAnswer.complete(false);
    await tester.pump(const Duration(seconds: 12));
    expect(room.exitCalls, 0);
    room.onClose();
    await tester.pump();
  });
  testWidgets('auto-exit timeout and late confirmation cause only one exit', (
    tester,
  ) async {
    final room = _Room()
      ..autoExitEnable.value = true
      ..autoExitMinutes.value = 0;
    room.setAutoExit();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 10));
    expect(room.exitCalls, 1);
    room.autoExitAnswer.complete(false);
    await tester.pump();
    expect(room.exitCalls, 1);
    room.onClose();
    await tester.pump();
  });
  testWidgets(
    'quality label follows the actual server quality of the selected line',
    (tester) async {
      final room = _Room();
      room.rxSite.value = Site(
        id: 'douyu',
        liveSite: _PlaySite(),
        logo: '',
        name: '斗鱼',
      );
      room.qualites.add(LivePlayQuality(quality: '原画1080P60', data: 0));
      room.currentQuality = 0;
      room.detail.value = LiveRoomDetail(
        roomId: '1',
        title: '',
        cover: '',
        userName: '',
        userAvatar: '',
        online: 0,
        status: true,
        url: '',
      );
      room.getPlayUrl();
      await tester.pump();
      expect(room.currentQualityInfo.value, '实际：高清');
      room.changePlayLine(1);
      await tester.pump();
      expect(room.currentQualityInfo.value, '原画1080P60');
      room.onClose();
      await tester.pump();
    },
  );
  testWidgets(
    'switching platform clears old quality, stream and profile data',
    (tester) async {
      final room = _SwitchRoom();
      room.qualites.add(LivePlayQuality(quality: 'old', data: 0));
      room.playUrls.add('https://example.invalid/old');
      room.currentQuality = 0;
      room.currentLineIndex = 0;
      room.currentQualityInfo.value = 'old quality';
      room.currentLineInfo.value = 'old line';
      room.liveStatus.value = true;
      room.online.value = 10;
      room.followed.value = true;
      room.disableAutoScroll.value = true;
      room.resetRoom(Sites.allSites['bilibili']!, '2');
      expect(room.qualites, isEmpty);
      expect(room.playUrls, isEmpty);
      expect(room.currentQuality, -1);
      expect(room.currentLineIndex, -1);
      expect(room.currentQualityInfo.value, '');
      expect(room.currentLineInfo.value, '');
      expect(room.liveStatus.value, isFalse);
      expect(room.online.value, 0);
      expect(room.followed.value, isFalse);
      expect(room.disableAutoScroll.value, isFalse);
      await tester.pump();
      expect(room.loads, 1);
      room.onClose();
      await tester.pump();
    },
  );
}
