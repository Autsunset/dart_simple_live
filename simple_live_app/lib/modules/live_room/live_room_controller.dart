import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/crash_diagnostics.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/modules/live_room/widgets/room_quick_switch.dart';
import 'package:simple_live_app/widgets/douyu_cookie_dialog.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class LiveRoomController extends PlayerController with WidgetsBindingObserver {
  final Site pSite;
  final String pRoomId;
  late LiveDanmaku liveDanmaku;
  LiveRoomController({required this.pSite, required this.pRoomId}) {
    rxSite = pSite.obs;
    rxRoomId = pRoomId.obs;
    liveDanmaku = site.liveSite.getDanmaku();
    // 抖音应该默认是竖屏的
    if (site.id == "douyin") {
      isVertical.value = true;
    }
  }

  late Rx<Site> rxSite;
  Site get site => rxSite.value;
  late Rx<String> rxRoomId;
  String get roomId => rxRoomId.value;

  Rx<LiveRoomDetail?> detail = Rx<LiveRoomDetail?>(null);
  var online = 0.obs;
  var followed = false.obs;
  var liveStatus = false.obs;
  RxList<LiveSuperChatMessage> superChats = RxList<LiveSuperChatMessage>();

  /// 滚动控制
  final ScrollController scrollController = ScrollController();

  /// 聊天信息
  RxList<LiveMessage> messages = RxList<LiveMessage>();

  /// 清晰度数据
  RxList<LivePlayQuality> qualites = RxList<LivePlayQuality>();

  /// 当前清晰度
  var currentQuality = -1;
  var currentQualityInfo = "".obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();

  Map<String, String>? playHeaders;
  List<String>? _returnedQualities;

  /// 当前线路
  var currentLineIndex = -1;
  var currentLineInfo = "".obs;

  /// 退出倒计时
  var countdown = 60.obs;

  Timer? autoExitTimer;
  Timer? _autoExitConfirmationTimer;
  int _autoExitRequestId = 0;

  /// 设置的自动关闭时间（分钟）
  var autoExitMinutes = 60.obs;

  ///是否延迟自动关闭
  var delayAutoExit = false.obs;

  /// 是否启用自动关闭
  var autoExitEnable = false.obs;

  /// 是否禁用自动滚动聊天栏
  /// - 当用户向上滚动聊天栏时，不再自动滚动
  var disableAutoScroll = false.obs;

  /// Remember the last picker tab across portrait/landscape openings.
  final quickSwitchTab = 0.obs;

  /// 是否处于后台
  var isBackground = false;

  /// 直播间加载失败
  var loadError = false.obs;
  Object? error;
  StackTrace? errorStackTrace;

  bool get roomClosed => isClosed || playerClosing;
  static const maxChatMessages = 500;
  static const maxSuperChatMessages = 100;
  bool _chatScrollScheduled = false;
  Timer? _retryTimer;
  int _lineRequestId = 0;
  bool _playbackReady = false;

  void _cancelPlaybackRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  static const chatFlushInterval = Duration(milliseconds: 150);
  final Queue<LiveMessage> _pendingMessages = Queue<LiveMessage>();
  Timer? _chatFlushTimer;
  final Map<String, Pattern?> _shieldPatterns = {};

  void _appendMessages(Iterable<LiveMessage> batch) {
    final limit = disableAutoScroll.value ? maxChatMessages : 200;
    final combined = [...messages, ...batch];
    messages.value = combined.length > limit
        ? combined.sublist(combined.length - limit)
        : combined;
  }

  void _queueMessage(LiveMessage message) {
    _pendingMessages.addLast(message);
    if (_pendingMessages.length > maxChatMessages) {
      _pendingMessages.removeFirst();
    }
    _chatFlushTimer ??= Timer(chatFlushInterval, _flushMessages);
  }

  void _flushMessages() {
    _chatFlushTimer?.cancel();
    _chatFlushTimer = null;
    if (roomClosed || _pendingMessages.isEmpty) return;
    final batch = _pendingMessages.toList();
    _pendingMessages.clear();
    _appendMessages(batch);
    if (!_chatScrollScheduled && !isBackground && !disableAutoScroll.value) {
      _chatScrollScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatScrollScheduled = false;
        chatScrollToBottom();
      });
    }
    if (liveStatus.value && !isBackground) {
      addDanmaku(
        batch
            .map(
              (msg) => DanmakuContentItem(
                msg.message,
                color: Color.fromARGB(
                  255,
                  msg.color.r,
                  msg.color.g,
                  msg.color.b,
                ),
              ),
            )
            .toList(),
      );
    }
  }

  void _cancelPendingMessages() {
    _chatFlushTimer?.cancel();
    _chatFlushTimer = null;
    _pendingMessages.clear();
  }

  bool _isShielded(String message) {
    final keywords = AppSettingsController.instance.shieldList;
    _shieldPatterns.removeWhere((keyword, _) => !keywords.contains(keyword));
    for (final keyword in keywords) {
      if (!_shieldPatterns.containsKey(keyword)) {
        Pattern? pattern = keyword;
        if (Utils.isRegexFormat(keyword)) {
          try {
            pattern = RegExp(Utils.removeRegexFormat(keyword));
          } on FormatException {
            pattern = null;
            Log.d("关键词：$keyword 正则格式错误");
          }
        }
        _shieldPatterns[keyword] = pattern;
      }
      final pattern = _shieldPatterns[keyword];
      if (pattern != null && message.contains(pattern)) return true;
    }
    return false;
  }

  void _appendSuperChats(Iterable<LiveSuperChatMessage> incoming) {
    final now = DateTime.now();
    final merged = {for (final message in superChats) message.key: message};
    for (final message in incoming) {
      if (message.endTime.isAfter(now)) merged[message.key] = message;
    }
    final active = merged.values.where((m) => m.endTime.isAfter(now)).toList()
      ..sort((a, b) => a.endTime.compareTo(b.endTime));
    superChats.value = active.length > maxSuperChatMessages
        ? active.sublist(active.length - maxSuperChatMessages)
        : active;
  }

  void _trimSuperChats() {
    final now = DateTime.now();
    superChats.removeWhere((message) => message.endTime.isBefore(now));
    if (superChats.length > maxSuperChatMessages) {
      superChats.removeRange(0, superChats.length - maxSuperChatMessages);
    }
  }

  int _roomRequestId = 0;
  int _playUrlRequestId = 0;

  // 开播时长状态变量
  var liveDuration = "00:00:00".obs;
  Timer? _liveDurationTimer;
  Timer? _playbackHealthTimer;

  void _samplePlaybackHealth() {
    if (roomClosed) return;
    unawaited(
      CrashDiagnostics.samplePlayback(
        'site=${site.id} quality=${currentQualityInfo.value} '
        'chat=${messages.length} sc=${superChats.length} '
        'background=$isBackground',
      ),
    );
  }

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    if (FollowService.instance.followList.isEmpty) {
      FollowService.instance.loadData();
    }
    initAutoExit();
    showDanmakuState.value = AppSettingsController.instance.danmuEnable.value;
    followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
    loadData();

    scrollController.addListener(scrollListener);
    if (Platform.isAndroid) {
      _samplePlaybackHealth();
      _playbackHealthTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        _trimSuperChats();
        _samplePlaybackHealth();
      });
    }

    super.onInit();
  }

  void scrollListener() {
    if (!scrollController.hasClients || roomClosed) return;
    final position = scrollController.position;
    if (position.userScrollDirection == ScrollDirection.forward) {
      disableAutoScroll.value = true;
    } else if (position.extentAfter <= 24) {
      disableAutoScroll.value = false;
    }
  }

  /// 初始化自动关闭倒计时
  void initAutoExit() {
    if (AppSettingsController.instance.autoExitEnable.value) {
      autoExitEnable.value = true;
      autoExitMinutes.value =
          AppSettingsController.instance.autoExitDuration.value;
      setAutoExit();
    } else {
      autoExitMinutes.value =
          AppSettingsController.instance.roomAutoExitDuration.value;
    }
  }

  void setAutoExit() {
    final requestId = ++_autoExitRequestId;
    autoExitTimer?.cancel();
    _autoExitConfirmationTimer?.cancel();
    _autoExitConfirmationTimer = null;
    if (roomClosed || !autoExitEnable.value) return;
    countdown.value = autoExitMinutes.value * 60;
    autoExitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (roomClosed || requestId != _autoExitRequestId) {
        timer.cancel();
        return;
      }
      countdown.value -= 1;
      if (countdown.value <= 0) {
        timer.cancel();
        unawaited(_confirmAutoExit(requestId));
      }
    });
  }

  Future<bool> showAutoExitConfirmation() => Utils.showAlertDialog(
    "定时关闭已到时,是否延迟关闭?",
    title: "延迟关闭",
    confirm: "延迟",
    cancel: "关闭",
    selectable: true,
  );

  void exitApplication() => exit(0);

  bool _autoExitIsCurrent(int requestId) =>
      !roomClosed && autoExitEnable.value && requestId == _autoExitRequestId;

  Future<void> _exitIfCurrent(int requestId) async {
    if (!_autoExitIsCurrent(requestId)) return;
    try {
      await WakelockPlus.disable();
      if (!_autoExitIsCurrent(requestId)) return;
      ++_autoExitRequestId; // A timeout and a dialog result can fire together.
      _autoExitConfirmationTimer?.cancel();
      _autoExitConfirmationTimer = null;
      exitApplication();
    } catch (e, stack) {
      Log.e("定时关闭失败: $e", stack);
    }
  }

  Future<void> _confirmAutoExit(int requestId) async {
    _autoExitConfirmationTimer = Timer(const Duration(seconds: 10), () {
      unawaited(_exitIfCurrent(requestId));
    });
    try {
      final delay = await showAutoExitConfirmation();
      if (!_autoExitIsCurrent(requestId)) return;
      _autoExitConfirmationTimer?.cancel();
      _autoExitConfirmationTimer = null;
      delayAutoExit.value = delay;
      if (delay) {
        showAutoExitSheet();
        setAutoExit();
      } else {
        await _exitIfCurrent(requestId);
      }
    } catch (e, stack) {
      Log.e("定时关闭确认失败: $e", stack);
    }
  }
  // 弹窗逻辑

  void refreshRoom() {
    if (roomClosed) return;
    //messages.clear();
    superChats.clear();
    _stopDanmaku();

    loadData();
  }

  /// 聊天栏始终滚动到底部
  void chatScrollToBottom() {
    if (!roomClosed && scrollController.hasClients) {
      // 如果手动上拉过，就不自动滚动到底部
      if (disableAutoScroll.value) {
        return;
      }
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    }
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    liveDanmaku.onMessage = onWSMessage;
    liveDanmaku.onClose = onWSClose;
    liveDanmaku.onReady = onWSReady;
  }

  /// 接收到WebSocket信息
  void onWSMessage(LiveMessage msg) {
    if (roomClosed) return;
    if (msg.type == LiveMessageType.chat) {
      if (_isShielded(msg.message)) return;
      _queueMessage(msg);
    } else if (msg.type == LiveMessageType.online) {
      if (msg.data is int) online.value = msg.data;
    } else if (msg.type == LiveMessageType.superChat) {
      if (msg.data is LiveSuperChatMessage) {
        _appendSuperChats([msg.data as LiveSuperChatMessage]);
      }
    }
  }

  /// 添加一条系统消息
  void addSysMsg(String msg) {
    if (roomClosed) return;
    _flushMessages();
    _appendMessages([
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "LiveSysMessage",
        message: msg,
        color: LiveMessageColor.white,
      ),
    ]);
  }

  /// 接收到WebSocket关闭信息
  void onWSClose(String msg) {
    addSysMsg(msg);
  }

  /// WebSocket准备就绪
  void onWSReady() {
    addSysMsg("弹幕服务器连接正常");
  }

  /// 加载直播间信息
  void loadData() async {
    if (roomClosed) return;
    _playbackReady = false;
    _cancelPlaybackRetry();
    ++_playUrlRequestId;
    final requestId = ++_roomRequestId;
    final requestedSite = site;
    final requestedRoomId = roomId;
    try {
      SmartDialog.showLoading(msg: "");
      loadError.value = false;
      error = null;
      errorStackTrace = null;
      update();
      addSysMsg("正在读取直播间信息");
      final roomDetail = await requestedSite.liveSite.getRoomDetail(
        roomId: requestedRoomId,
      );
      if (roomClosed || requestId != _roomRequestId) return;
      detail.value = roomDetail;

      if (site.id == Constant.kDouyin) {
        // 1.6.0之前收藏的WebRid
        // 1.6.0收藏的RoomID
        // 1.6.0之后改回WebRid
        if (detail.value!.roomId != roomId) {
          var oldId = roomId;
          rxRoomId.value = detail.value!.roomId;
          if (followed.value) {
            // 更新关注列表
            DBService.instance.deleteFollow("${site.id}_$oldId");
            DBService.instance.addFollow(
              FollowUser(
                id: "${site.id}_$roomId",
                roomId: roomId,
                siteId: site.id,
                userName: detail.value!.userName,
                face: detail.value!.userAvatar,
                addTime: DateTime.now(),
              ),
            );
          } else {
            followed.value = DBService.instance.getFollowExist(
              "${site.id}_$roomId",
            );
          }
        }
      }

      getSuperChatMessage();

      addHistory();
      // 确认房间关注状态
      followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
      online.value = detail.value!.online;
      liveStatus.value = detail.value!.status || detail.value!.isRecord;
      if (liveStatus.value) {
        getPlayQualites();
      }
      if (detail.value!.isRecord) {
        addSysMsg("当前主播未开播，正在轮播录像");
      }
      addSysMsg("开始连接弹幕服务器");
      initDanmau();
      await liveDanmaku.start(detail.value?.danmakuData);
      if (roomClosed || requestId != _roomRequestId) return;
      startLiveDurationTimer(); // 启动开播时长定时器
    } catch (e, stackTrace) {
      if (roomClosed || requestId != _roomRequestId) return;
      Log.e("直播间加载失败: $e", stackTrace);
      //SmartDialog.showToast(e.toString());
      loadError.value = true;
      error = e;
      errorStackTrace = stackTrace;
    } finally {
      if (!roomClosed && requestId == _roomRequestId) {
        SmartDialog.dismiss(status: SmartStatus.loading);
      }
    }
  }

  /// 初始化播放器
  void getPlayQualites() async {
    final requestId = _roomRequestId;
    final roomDetail = detail.value;
    if (roomDetail == null || roomClosed) return;
    qualites.clear();
    currentQuality = -1;

    try {
      var playQualites = await site.liveSite.getPlayQualites(
        detail: roomDetail,
      );
      if (roomClosed || requestId != _roomRequestId) return;

      if (playQualites.isEmpty) {
        SmartDialog.showToast("无法读取播放清晰度");
        return;
      }
      qualites.value = playQualites;
      var qualityLevel = await getQualityLevel();
      if (roomClosed || requestId != _roomRequestId) return;
      if (qualityLevel == 2) {
        //最高
        currentQuality = 0;
      } else if (qualityLevel == 0) {
        //最低
        currentQuality = playQualites.length - 1;
      } else {
        //中间值
        int middle = (playQualites.length / 2).floor();
        currentQuality = middle;
      }

      getPlayUrl();
    } catch (e) {
      if (roomClosed || requestId != _roomRequestId) return;
      Log.logPrint(e);
      SmartDialog.showToast("无法读取播放清晰度");
    }
  }

  Future<int> getQualityLevel() async {
    var qualityLevel = AppSettingsController.instance.qualityLevel.value;
    try {
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult.first == ConnectivityResult.mobile) {
        qualityLevel =
            AppSettingsController.instance.qualityLevelCellular.value;
      }
    } catch (e) {
      Log.logPrint(e);
    }
    return qualityLevel;
  }

  void getPlayUrl() async {
    _playbackReady = false;
    _cancelPlaybackRetry();
    final requestId = _roomRequestId;
    final playUrlRequestId = ++_playUrlRequestId;
    final roomDetail = detail.value;
    if (roomClosed ||
        roomDetail == null ||
        currentQuality < 0 ||
        currentQuality >= qualites.length) {
      return;
    }
    final quality = qualites[currentQuality];
    playUrls.clear();
    _returnedQualities = null;
    currentQualityInfo.value = quality.quality;
    currentLineInfo.value = "";
    currentLineIndex = -1;
    try {
      var playUrl = await site.liveSite.getPlayUrls(
        detail: roomDetail,
        quality: quality,
      );
      if (roomClosed ||
          requestId != _roomRequestId ||
          playUrlRequestId != _playUrlRequestId) {
        return;
      }
      if (playUrl.urls.isEmpty) {
        SmartDialog.showToast("无法读取播放地址");
        return;
      }
      playUrls.value = playUrl.urls;
      playHeaders = playUrl.headers;
      _returnedQualities = playUrl.qualities;
      currentLineIndex = 0;
      currentLineInfo.value = "线路${currentLineIndex + 1}";
      mediaErrorRetryCount = 0;
      await initPlaylist(requestId, playUrlRequestId);
    } catch (e, stackTrace) {
      if (roomClosed ||
          requestId != _roomRequestId ||
          playUrlRequestId != _playUrlRequestId) {
        return;
      }
      Log.e("读取播放地址失败: $e", stackTrace);
      SmartDialog.showToast("无法读取播放地址");
    }
  }

  void changePlayLine(int index) {
    if (roomClosed || index < 0 || index >= playUrls.length) {
      return;
    }
    _cancelPlaybackRetry();
    ++_lineRequestId;
    currentLineIndex = index;
    //重置错误次数
    mediaErrorRetryCount = 0;
    setPlayer();
  }

  Future<void> initPlaylist(int requestId, int playUrlRequestId) async {
    if (playUrls.isEmpty ||
        roomClosed ||
        requestId != _roomRequestId ||
        playUrlRequestId != _playUrlRequestId) {
      return;
    }
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    _updateReturnedQuality();
    errorMsg.value = "";

    final mediaList = playUrls.map((url) {
      var finalUrl = url;
      if (AppSettingsController.instance.playerForceHttps.value) {
        finalUrl = finalUrl.replaceAll("http://", "https://");
      }
      return Media(finalUrl, httpHeaders: playHeaders);
    }).toList();

    await runPlayerOperation(
      () async {
        await initializePlayer();
        if (roomClosed ||
            requestId != _roomRequestId ||
            playUrlRequestId != _playUrlRequestId) {
          return;
        }
        _playbackReady = true;
        await player.open(Playlist(mediaList));
      },
      isCurrent: () =>
          requestId == _roomRequestId && playUrlRequestId == _playUrlRequestId,
    );
  }

  void _updateReturnedQuality() {
    if (currentQuality < 0 || currentQuality >= qualites.length) return;
    final requested = qualites[currentQuality].quality;
    final returned = _returnedQualities;
    final actual =
        returned != null &&
            currentLineIndex >= 0 &&
            currentLineIndex < returned.length
        ? returned[currentLineIndex]
        : '';
    currentQualityInfo.value = actual.isEmpty || actual == requested
        ? requested
        : '实际：$actual';
  }

  Future<void> setPlayer() async {
    final requestId = _roomRequestId;
    final urlRequestId = _playUrlRequestId;
    final lineRequestId = _lineRequestId;
    final lineIndex = currentLineIndex;
    if (roomClosed ||
        !_playbackReady ||
        lineIndex < 0 ||
        lineIndex >= playUrls.length) {
      return;
    }
    currentLineInfo.value = "线路${lineIndex + 1}";
    _updateReturnedQuality();
    errorMsg.value = "";
    try {
      await runPlayerOperation(
        () => player.jump(lineIndex),
        isCurrent: () =>
            requestId == _roomRequestId &&
            urlRequestId == _playUrlRequestId &&
            lineRequestId == _lineRequestId,
      );
    } catch (e, stackTrace) {
      if (roomClosed ||
          requestId != _roomRequestId ||
          urlRequestId != _playUrlRequestId ||
          lineRequestId != _lineRequestId) {
        return;
      }
      Log.e("切换播放线路失败: $e", stackTrace);
      mediaError(e.toString());
    }
  }

  @override
  void mediaEnd() {
    super.mediaEnd();
    _schedulePlaybackRetry();
  }

  int mediaErrorRetryCount = 0;
  @override
  void mediaError(String error) {
    super.mediaError(error);
    _schedulePlaybackRetry(error: error);
  }

  void _schedulePlaybackRetry({String? error}) {
    if (roomClosed ||
        !_playbackReady ||
        _retryTimer != null ||
        currentLineIndex < 0 ||
        currentLineIndex >= playUrls.length) {
      return;
    }
    final requestId = _roomRequestId;
    final urlRequestId = _playUrlRequestId;
    final lineRequestId = _lineRequestId;
    // mpv can emit error and completed for the same failure. Coalesce the burst.
    _retryTimer = Timer(const Duration(seconds: 1), () {
      _retryTimer = null;
      if (roomClosed ||
          !_playbackReady ||
          requestId != _roomRequestId ||
          urlRequestId != _playUrlRequestId ||
          lineRequestId != _lineRequestId) {
        return;
      }
      if (mediaErrorRetryCount < 2) {
        mediaErrorRetryCount++;
        Log.d("播放中断，尝试第$mediaErrorRetryCount次刷新");
        unawaited(setPlayer());
      } else if (currentLineIndex + 1 < playUrls.length) {
        changePlayLine(currentLineIndex + 1);
      } else {
        _playbackReady = false;
        if (error == null) {
          liveStatus.value = false;
        } else {
          errorMsg.value = "播放失败";
          SmartDialog.showToast("播放失败:$error");
        }
      }
    });
  }

  /// 读取SC
  void getSuperChatMessage() async {
    final requestId = _roomRequestId;
    try {
      var sc = await site.liveSite.getSuperChatMessage(
        roomId: detail.value!.roomId,
      );
      if (roomClosed || requestId != _roomRequestId) return;
      _appendSuperChats(sc);
    } catch (e) {
      Log.logPrint(e);
      addSysMsg("SC读取失败");
    }
  }

  /// 移除掉已到期的SC
  void removeSuperChats() async {
    var now = DateTime.now().millisecondsSinceEpoch;
    superChats.value = superChats
        .where((x) => x.endTime.millisecondsSinceEpoch > now)
        .toList();
  }

  /// 添加历史记录
  void addHistory() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    var history = DBService.instance.getHistory(id);
    if (history != null) {
      history.updateTime = DateTime.now();
    }
    history ??= History(
      id: id,
      roomId: roomId,
      siteId: site.id,
      userName: detail.value?.userName ?? "",
      face: detail.value?.userAvatar ?? "",
      updateTime: DateTime.now(),
    );

    DBService.instance.addOrUpdateHistory(history);
  }

  /// 关注用户
  void followUser() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    DBService.instance.addFollow(
      FollowUser(
        id: id,
        roomId: roomId,
        siteId: site.id,
        userName: detail.value?.userName ?? "",
        face: detail.value?.userAvatar ?? "",
        addTime: DateTime.now(),
      ),
    );
    followed.value = true;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  /// 取消关注用户
  void removeFollowUser() async {
    if (detail.value == null) {
      return;
    }
    if (!await Utils.showAlertDialog("确定要取消关注该用户吗？", title: "取消关注")) {
      return;
    }

    var id = "${site.id}_$roomId";
    DBService.instance.deleteFollow(id);
    followed.value = false;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  void share() {
    if (detail.value == null) {
      return;
    }
    SharePlus.instance.share(ShareParams(uri: Uri.parse(detail.value!.url)));
  }

  void copyUrl() {
    if (detail.value == null) {
      return;
    }
    Utils.copyToClipboard(detail.value!.url);
    SmartDialog.showToast("已复制直播间链接");
  }

  /// 复制新生成的直播流
  void copyPlayUrl() async {
    // 未开播不复制
    if (!liveStatus.value) {
      return;
    }
    var playUrl = await site.liveSite.getPlayUrls(
      detail: detail.value!,
      quality: qualites[currentQuality],
    );
    if (playUrl.urls.isEmpty) {
      SmartDialog.showToast("无法读取播放地址");
      return;
    }
    Utils.copyToClipboard(playUrl.urls.first);
    SmartDialog.showToast("已复制播放直链");
  }

  /// 底部打开播放器设置
  void showDanmuSettingsSheet() {
    Utils.showBottomSheet(
      title: "弹幕设置",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          DanmuSettingsView(
            danmakuController: danmakuController,
            onTapDanmuShield: () {
              Get.back();
              showDanmuShield();
            },
          ),
        ],
      ),
    );
  }

  void showVolumeSlider(BuildContext targetContext) {
    SmartDialog.showAttach(
      targetContext: targetContext,
      alignment: Alignment.topCenter,
      displayTime: const Duration(seconds: 3),
      maskColor: const Color(0x00000000),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: AppStyle.radius12,
            color: Theme.of(context).cardColor,
          ),
          padding: AppStyle.edgeInsetsA4,
          child: Obx(
            () => SizedBox(
              width: 200,
              child: Slider(
                min: 0,
                max: 100,
                value: AppSettingsController.instance.playerVolume.value,
                onChanged: (newValue) {
                  player.setVolume(newValue);
                  AppSettingsController.instance.setPlayerVolume(newValue);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> showDouyuCookieConfiguration() => DouyuCookieDialog.configure();

  Future<void> configureDouyuCookie() async {
    if (roomClosed || site.id != Constant.kDouyu) return;
    final requestId = _roomRequestId;
    final saved = await showDouyuCookieConfiguration();
    if (saved && !roomClosed && requestId == _roomRequestId) {
      getPlayUrl();
    }
  }

  void showQualitySheet() {
    Utils.showBottomSheet(
      title: "切换清晰度",
      child: RadioGroup(
        groupValue: currentQuality,
        onChanged: (e) {
          Get.back();
          currentQuality = e ?? 0;
          getPlayUrl();
        },
        child: ListView.builder(
          itemCount: qualites.length + (site.id == Constant.kDouyu ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == qualites.length) {
              return ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('原画受限？配置斗鱼 Cookie'),
                subtitle: const Text('保存后按当前清晰度重新请求；仍受平台限制'),
                onTap: () {
                  Get.back();
                  configureDouyuCookie();
                },
              );
            }
            var item = qualites[i];
            return RadioListTile(value: i, title: Text(item.quality));
          },
        ),
      ),
    );
  }

  void showPlayUrlsSheet() {
    Utils.showBottomSheet(
      title: "切换线路",
      child: RadioGroup(
        groupValue: currentLineIndex,
        onChanged: (e) {
          Get.back();
          //currentLineIndex = i;
          //setPlayer();
          changePlayLine(e ?? 0);
        },
        child: ListView.builder(
          itemCount: playUrls.length,
          itemBuilder: (_, i) {
            return RadioListTile(
              value: i,
              title: Text("线路${i + 1}"),
              secondary: Text(playUrls[i].contains(".flv") ? "FLV" : "HLS"),
            );
          },
        ),
      ),
    );
  }

  void showPlayerSettingsSheet() {
    Utils.showBottomSheet(
      title: "画面尺寸",
      child: Obx(
        () => RadioGroup(
          groupValue: AppSettingsController.instance.scaleMode.value,
          onChanged: (e) {
            AppSettingsController.instance.setScaleMode(e ?? 0);
            updateScaleMode();
          },
          child: ListView(
            padding: AppStyle.edgeInsetsV12,
            children: const [
              RadioListTile(
                value: 0,
                title: Text("适应"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 1,
                title: Text("拉伸"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 2,
                title: Text("铺满"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 3,
                title: Text("16:9"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 4,
                title: Text("4:3"),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showDanmuShield() {
    TextEditingController keywordController = TextEditingController();

    void addKeyword() {
      if (keywordController.text.isEmpty) {
        SmartDialog.showToast("请输入关键词");
        return;
      }

      AppSettingsController.instance.addShieldList(
        keywordController.text.trim(),
      );
      keywordController.text = "";
    }

    Utils.showBottomSheet(
      title: "关键词屏蔽",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          TextField(
            controller: keywordController,
            decoration: InputDecoration(
              contentPadding: AppStyle.edgeInsetsH12,
              border: const OutlineInputBorder(),
              hintText: "请输入关键词",
              suffixIcon: TextButton.icon(
                onPressed: addKeyword,
                icon: const Icon(Icons.add),
                label: const Text("添加"),
              ),
            ),
            onSubmitted: (e) {
              addKeyword();
            },
          ),
          AppStyle.vGap12,
          Obx(
            () => Text(
              "已添加${AppSettingsController.instance.shieldList.length}个关键词（点击移除）",
              style: Get.textTheme.titleSmall,
            ),
          ),
          AppStyle.vGap12,
          Obx(
            () => Wrap(
              runSpacing: 12,
              spacing: 12,
              children: AppSettingsController.instance.shieldList
                  .map(
                    (item) => InkWell(
                      borderRadius: AppStyle.radius24,
                      onTap: () {
                        AppSettingsController.instance.removeShieldList(item);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: AppStyle.radius24,
                        ),
                        padding: AppStyle.edgeInsetsH12.copyWith(
                          top: 4,
                          bottom: 4,
                        ),
                        child: Text(item, style: Get.textTheme.bodyMedium),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  void showFollowUserSheet() {
    if (roomClosed) return;
    Utils.showBottomSheet(
      title: "切换直播间",
      child: RoomQuickSwitch(controller: this, close: () => Get.back()),
    );
  }

  void showAutoExitSheet() {
    if (AppSettingsController.instance.autoExitEnable.value &&
        !delayAutoExit.value) {
      SmartDialog.showToast("已设置了全局定时关闭");
      return;
    }
    Utils.showBottomSheet(
      title: "定时关闭",
      child: ListView(
        children: [
          Obx(
            () => SwitchListTile(
              title: Text("启用定时关闭", style: Get.textTheme.titleMedium),
              value: autoExitEnable.value,
              onChanged: (e) {
                autoExitEnable.value = e;

                setAutoExit();
                //controller.setAutoExitEnable(e);
              },
            ),
          ),
          Obx(
            () => ListTile(
              enabled: autoExitEnable.value,
              title: Text(
                "自动关闭时间：${autoExitMinutes.value ~/ 60}小时${autoExitMinutes.value % 60}分钟",
                style: Get.textTheme.titleMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                var value = await showTimePicker(
                  context: Get.context!,
                  initialTime: TimeOfDay(
                    hour: autoExitMinutes.value ~/ 60,
                    minute: autoExitMinutes.value % 60,
                  ),
                  initialEntryMode: TimePickerEntryMode.inputOnly,
                  builder: (_, child) {
                    return MediaQuery(
                      data: Get.mediaQuery.copyWith(
                        alwaysUse24HourFormat: true,
                      ),
                      child: child!,
                    );
                  },
                );
                if (value == null || (value.hour == 0 && value.minute == 0)) {
                  return;
                }
                var duration = Duration(
                  hours: value.hour,
                  minutes: value.minute,
                );
                autoExitMinutes.value = duration.inMinutes;
                AppSettingsController.instance.setRoomAutoExitDuration(
                  autoExitMinutes.value,
                );
                //setAutoExitDuration(duration.inMinutes);
                setAutoExit();
              },
            ),
          ),
        ],
      ),
    );
  }

  void openNaviteAPP() async {
    var naviteUrl = "";
    var webUrl = "";
    if (site.id == Constant.kBiliBili) {
      naviteUrl = "bilibili://live/${detail.value?.roomId}";
      webUrl = "https://live.bilibili.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyin) {
      var args = detail.value?.danmakuData as DouyinDanmakuArgs;
      naviteUrl = "snssdk1128://webcast_room?room_id=${args.roomId}";
      webUrl = "https://live.douyin.com/${args.webRid}";
    } else if (site.id == Constant.kHuya) {
      var args = detail.value?.danmakuData as HuyaDanmakuArgs;
      naviteUrl =
          "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide";
      webUrl = "https://www.huya.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyu) {
      naviteUrl =
          "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D${detail.value?.roomId}";
      webUrl = "https://www.douyu.com/${detail.value?.roomId}";
    }
    try {
      await launchUrlString(naviteUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法打开APP，将使用浏览器打开");
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  void resetRoom(Site site, String roomId) async {
    if (roomClosed) return;
    if (this.site == site && this.roomId == roomId) {
      return;
    }
    _playbackReady = false;
    _cancelPlaybackRetry();

    // Clear platform-specific data before any async stop/load can complete.
    detail.value = null;
    liveStatus.value = false;
    online.value = 0;
    followed.value = false;
    qualites.clear();
    playUrls.clear();
    playHeaders = null;
    _returnedQualities = null;
    currentQuality = -1;
    currentLineIndex = -1;
    currentQualityInfo.value = '';
    currentLineInfo.value = '';
    _liveDurationTimer?.cancel();
    liveDuration.value = '00:00:00';
    disableAutoScroll.value = false;

    rxSite.value = site;
    rxRoomId.value = roomId;
    final requestId = ++_roomRequestId;
    ++_playUrlRequestId;

    // 清除全部消息
    _stopDanmaku();
    messages.clear();
    superChats.clear();
    danmakuController?.clear();

    // 重新设置LiveDanmaku
    liveDanmaku = site.liveSite.getDanmaku();

    // 停止播放
    try {
      await runPlayerOperation(
        () => player.stop(),
        isCurrent: () => requestId == _roomRequestId,
      );
    } catch (e, stackTrace) {
      Log.e("停止旧直播流失败: $e", stackTrace);
    }

    // 刷新信息
    if (!roomClosed && requestId == _roomRequestId) loadData();
  }

  void copyErrorDetail() {
    Utils.copyToClipboard('''直播平台：${rxSite.value.name}
房间号：${rxRoomId.value}
错误信息：
${error?.toString()}
----------------
$errorStackTrace''');
    SmartDialog.showToast("已复制错误信息");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      Log.d("进入后台");
      //进入后台，关闭弹幕
      danmakuController?.clear();
      isBackground = true;
    } else
    //返回前台
    if (state == AppLifecycleState.resumed) {
      Log.d("返回前台");
      isBackground = false;
      danmakuController?.resume();
    }
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    if (roomClosed) return;
    danmakuController?.clear();
    _cancelPendingMessages();
    if (messages.length > 100) messages.removeRange(0, messages.length - 100);
    _trimSuperChats();
    _samplePlaybackHealth();
  }

  // 用于启动开播时长计算和更新的函数
  void startLiveDurationTimer() {
    // 如果不是直播状态或者 showTime 为空，则不启动定时器
    if (!(detail.value?.status ?? false) || detail.value?.showTime == null) {
      liveDuration.value = "00:00:00"; // 未开播时显示 00:00:00
      _liveDurationTimer?.cancel();
      return;
    }

    try {
      int startTimeStamp = int.parse(detail.value!.showTime!);
      // 取消之前的定时器
      _liveDurationTimer?.cancel();
      // 创建新的定时器，每秒更新一次
      _liveDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        int currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        int durationInSeconds = currentTimeStamp - startTimeStamp;

        int hours = durationInSeconds ~/ 3600;
        int minutes = (durationInSeconds % 3600) ~/ 60;
        int seconds = durationInSeconds % 60;

        String formattedDuration =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        liveDuration.value = formattedDuration;
      });
    } catch (e) {
      liveDuration.value = "--:--:--"; // 错误时显示 --:--:--
    }
  }

  void _stopDanmaku() {
    _cancelPendingMessages();
    final danmaku = liveDanmaku;
    danmaku.onMessage = null;
    danmaku.onClose = null;
    danmaku.onReady = null;
    unawaited(
      Future.sync(() => danmaku.stop()).catchError((
        Object e,
        StackTrace stack,
      ) {
        Log.e("关闭弹幕连接失败: $e", stack);
      }),
    );
  }

  @override
  void onClose() {
    playerClosing = true;
    _playbackReady = false;
    _cancelPlaybackRetry();
    ++_roomRequestId;
    ++_playUrlRequestId;
    WidgetsBinding.instance.removeObserver(this);
    scrollController.removeListener(scrollListener);
    scrollController.dispose();
    autoExitTimer?.cancel();
    _autoExitConfirmationTimer?.cancel();
    ++_autoExitRequestId;

    _stopDanmaku();
    danmakuController = null;
    _liveDurationTimer?.cancel(); // 页面关闭时取消定时器
    _playbackHealthTimer?.cancel();
    super.onClose();
  }
}
