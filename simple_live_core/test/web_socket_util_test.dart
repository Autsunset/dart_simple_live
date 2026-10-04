import 'dart:async';
import 'dart:io';

import 'package:simple_live_core/src/common/web_socket_util.dart';
import 'package:test/test.dart';

void main() {
  test('malformed message does not stop later danmaku messages', () {
    final received = <String>[];
    final socket = WebScoketUtils(
      url: 'wss://example.invalid',
      heartBeatTime: 1000,
      onMessage: (data) {
        if (data == 'malformed') throw const FormatException('bad packet');
        received.add(data as String);
      },
    );

    expect(() => socket.receiveMessage('malformed'), returnsNormally);
    socket.receiveMessage('valid');

    expect(received, ['valid']);
  });

  test('closing during handshake cannot resurrect a connection', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final request = Completer<HttpRequest>();
    server.listen(request.complete);
    var ready = 0;
    final socket = WebScoketUtils(
      url: 'ws://127.0.0.1:${server.port}',
      heartBeatTime: 5,
      onReady: () => ready++,
    );
    addTearDown(() async {
      socket.close();
      await server.close(force: true);
    });
    final connecting = socket.connect();
    final handshake = await request.future;
    socket.close();
    final peer = await WebSocketTransformer.upgrade(handshake);
    await connecting;
    expect(ready, 0);
    expect(socket.status, SocketStatus.closed);
    expect(socket.heartBeatTimer, isNull);
    expect(socket.reconnectTimer, isNull);
    await peer.close();
  });

  test('a newer connection wins over a slow previous handshake', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final firstRequest = Completer<HttpRequest>();
    final peers = <WebSocket>[];
    var requests = 0;
    server.listen((request) async {
      if (++requests == 1) {
        firstRequest.complete(request);
      } else {
        peers.add(await WebSocketTransformer.upgrade(request));
      }
    });
    var ready = 0;
    final socket = WebScoketUtils(
      url: 'ws://127.0.0.1:${server.port}',
      heartBeatTime: 1000,
      onReady: () => ready++,
    );
    addTearDown(() async {
      socket.close();
      for (final peer in peers) {
        await peer.close();
      }
      await server.close(force: true);
    });
    final first = socket.connect();
    final handshake = await firstRequest.future;
    await socket.connect();
    peers.add(await WebSocketTransformer.upgrade(handshake));
    await first;
    expect(ready, 1);
    expect(socket.status, SocketStatus.connected);
  });

  test(
    'failed handshakes retry finitely without unhandled stream errors',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var attempts = 0;
      server.listen((request) async {
        attempts++;
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      });
      final exhausted = Completer<void>();
      final socket = WebScoketUtils(
        url: 'ws://127.0.0.1:${server.port}',
        heartBeatTime: 5,
        reconnectDelay: const Duration(milliseconds: 5),
        onClose: (message) {
          if (message.contains('重连超过') && !exhausted.isCompleted) {
            exhausted.complete();
          }
        },
      )..maxReconnectTime = 2;
      addTearDown(() async {
        socket.close();
        await server.close(force: true);
      });
      await socket.connect();
      await exhausted.future.timeout(const Duration(seconds: 3));
      expect(
        attempts,
        6,
      ); // initial + two retries, each with a fallback attempt
      expect(socket.status, SocketStatus.closed);
      expect(socket.reconnectTimer, isNull);
      expect(socket.heartBeatTimer, isNull);
    },
  );

  test(
    'async callback errors are contained and later messages still arrive',
    () async {
      final received = <String>[];
      final socket = WebScoketUtils(
        url: 'ws://example.invalid',
        heartBeatTime: 0,
        onMessage: (data) async {
          await Future<void>.delayed(Duration.zero);
          if (data == 'bad') throw const FormatException('bad async packet');
          received.add(data as String);
        },
      );
      socket.receiveMessage('bad');
      socket.receiveMessage('ok');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, ['ok']);
      socket.close();
    },
  );

  test('explicit close cancels a scheduled retry', () async {
    final socket = WebScoketUtils(
      url: 'ws://example.invalid',
      heartBeatTime: 5,
      reconnectDelay: const Duration(milliseconds: 5),
    );
    socket.reconnect();
    socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(socket.webSocket, isNull);
    expect(socket.reconnectTimer, isNull);
    expect(socket.status, SocketStatus.closed);
  });
}
