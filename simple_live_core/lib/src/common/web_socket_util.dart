import 'dart:async';

import 'package:simple_live_core/src/common/core_log.dart';
import 'package:web_socket_channel/io.dart';

enum SocketStatus { connected, failed, closed }

class WebScoketUtils {
  SocketStatus status = SocketStatus.closed;
  final String url;
  final String? backupUrl;
  final int heartBeatTime;
  final Function(dynamic)? onMessage;
  final Function(String msg)? onClose;
  final Function()? onReconnect;
  final Function()? onReady;
  final Function()? onHeartBeat;
  final Duration reconnectDelay;
  Map<String, dynamic>? headers;

  WebScoketUtils({
    required this.url,
    required this.heartBeatTime,
    this.onMessage,
    this.onClose,
    this.onReconnect,
    this.onReady,
    this.onHeartBeat,
    this.headers,
    this.backupUrl,
    this.reconnectDelay = const Duration(seconds: 5),
  });

  IOWebSocketChannel? webSocket;
  Timer? heartBeatTimer;
  int reconnectTime = 0;
  Timer? reconnectTimer;
  int maxReconnectTime = 5;
  StreamSubscription<dynamic>? streamSubscription;
  int _generation = 0;

  Future<void> connect({bool retry = false}) async {
    close();
    final generation = _generation;
    var connected = false;
    try {
      final wsurl = retry && (backupUrl?.isNotEmpty ?? false)
          ? backupUrl!
          : url;
      final channel = IOWebSocketChannel.connect(
        wsurl,
        connectTimeout: const Duration(seconds: 10),
        headers: headers,
      );
      webSocket = channel;
      // Subscribe before awaiting the handshake: connection errors are also
      // delivered on the stream, and must have a handler from the outset.
      streamSubscription = channel.stream.listen(
        (data) {
          if (generation == _generation && connected) receiveMessage(data);
        },
        onError: (Object error, StackTrace stack) {
          if (generation == _generation && connected) onError(error, stack);
        },
        onDone: () {
          if (generation == _generation && connected) onDone();
        },
      );
      await channel.ready;
      if (generation != _generation) return;
      connected = true;
      ready();
    } catch (error, stack) {
      if (generation != _generation) return;
      if (!retry) {
        await connect(retry: true);
      } else {
        onError(error, stack);
      }
    }
  }

  void ready() {
    status = SocketStatus.connected;
    final generation = _generation;
    _notify(() => onReady?.call());
    if (generation == _generation && status == SocketStatus.connected) {
      initHeartBeat();
    }
  }

  void initHeartBeat() {
    heartBeatTimer?.cancel();
    if (heartBeatTime <= 0) return;
    final generation = _generation;
    heartBeatTimer = Timer.periodic(Duration(milliseconds: heartBeatTime), (_) {
      if (generation == _generation && status == SocketStatus.connected) {
        _notify(() => onHeartBeat?.call());
      }
    });
  }

  void receiveMessage(dynamic data) {
    reconnectTime = 0;
    _notify(() => onMessage?.call(data));
  }

  void onError(Object error, Object stack) {
    final generation = _generation;
    status = SocketStatus.failed;
    _notify(() => onClose?.call(error.toString()));
    if (generation == _generation) reconnect();
  }

  void onDone() {
    if (status == SocketStatus.closed) return;
    final generation = _generation;
    _notify(() => onReconnect?.call());
    if (generation == _generation) reconnect();
  }

  void sendMessage(dynamic message) {
    if (status != SocketStatus.connected) return;
    try {
      webSocket?.sink.add(message);
    } catch (error, stack) {
      onError(error, stack);
    }
  }

  void close() {
    ++_generation;
    status = SocketStatus.closed;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    heartBeatTimer?.cancel();
    heartBeatTimer = null;
    final subscription = streamSubscription;
    streamSubscription = null;
    final channel = webSocket;
    webSocket = null;
    _notify(() => subscription?.cancel());
    _notify(() => channel?.sink.close());
  }

  void reconnect() {
    close();
    if (reconnectTime >= maxReconnectTime) {
      _notify(() => onClose?.call("重连超过最大次数，与服务器断开连接"));
      return;
    }
    reconnectTime++;
    final generation = _generation;
    reconnectTimer = Timer(reconnectDelay, () {
      reconnectTimer = null;
      if (generation == _generation) unawaited(connect());
    });
  }

  void _notify(FutureOr<dynamic> Function() callback) {
    // Includes async callbacks, heartbeat errors, and sink cleanup failures.
    unawaited(
      Future<dynamic>.sync(callback).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          CoreLog.e('弹幕回调失败: $error', stack);
        },
      ),
    );
  }
}
