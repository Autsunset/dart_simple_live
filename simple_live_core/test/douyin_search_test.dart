import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Object? Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = respond(options);
    return ResponseBody.fromString(
      response is String ? response : jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _DirectSite extends DouyinSite {
  final requestedIds = <String>[];

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    requestedIds.add(roomId);
    return LiveRoomDetail(
      roomId: '123456789012',
      title: 'offline room',
      cover: '',
      userName: 'anchor',
      userAvatar: 'avatar',
      online: 0,
      status: false,
      url: 'https://live.douyin.com/123456789012',
    );
  }
}

Map<String, Object?> _live({bool encoded = true, String id = '123456789012'}) {
  final room = {
    'title': 'room',
    'status': 2,
    'owner': {
      'web_rid': id,
      'nickname': 'anchor',
      'avatar_thumb': {
        'url_list': ['avatar'],
      },
    },
    'cover': {
      'url_list': ['cover'],
    },
    'stats': {'total_user': '123'},
  };
  return {
    'lives': {'rawdata': encoded ? jsonEncode(room) : room},
  };
}

void main() {
  late HttpClientAdapter original;
  late bool logging;
  setUp(() {
    logging = CoreLog.enableLog;
    CoreLog.enableLog = false;
    original = HttpClient.instance.dio.httpClientAdapter;
  });
  tearDown(() {
    HttpClient.instance.dio.httpClientAdapter = original;
    CoreLog.enableLog = logging;
  });

  test(
    'recognizes numbers and official room links, not usernames or hosts',
    () {
      for (final input in [
        ' 123456789012 ',
        'https://live.douyin.com/123456789012?from=search',
        'live.douyin.com/123456789012/',
        'share https://live.douyin.com/123456789012 enter',
      ]) {
        expect(DouyinSite.parseRoomId(input), '123456789012', reason: input);
      }
      expect(
        DouyinSite.parseRoomId(
          'https://webcast.amemv.com/webcast/reflow/7376429659866598196',
        ),
        '7376429659866598196',
      );
      for (final input in [
        '',
        'anchor123',
        'https://live.douyin.com/',
        'https://live.douyin.com/category/123',
        'https://live.douyin.com/abc',
        'https://notlive.douyin.com/123',
        'https://fake-live.douyin.com/123',
        'https://live.douyin.com.evil.invalid/123',
        'https://evil.invalid/live.douyin.com/123',
      ]) {
        expect(DouyinSite.parseRoomId(input), isNull, reason: input);
      }
    },
  );

  test(
    'room numbers bypass keyword search and do not repeat on page two',
    () async {
      HttpClient.instance.dio.httpClientAdapter = _Adapter(
        (_) => fail('Direct lookup must not request the search endpoint'),
      );
      final site = _DirectSite();
      final result = await site.searchRooms(' 123456789012 ');
      expect(result.items.single.roomId, '123456789012');
      expect(result.hasMore, isFalse);
      expect((await site.searchRooms('123456789012', page: 2)).items, isEmpty);
      expect(site.requestedIds, ['123456789012']);
    },
  );

  test(
    'anchor lookup via room link preserves offline status and avatar',
    () async {
      final site = _DirectSite();
      final result = await site.searchAnchors(
        'https://webcast.amemv.com/webcast/reflow/7376429659866598196',
      );
      expect(site.requestedIds, ['7376429659866598196']);
      expect(result.items.single.liveStatus, isFalse);
      expect(result.items.single.avatar, 'avatar');
      expect(result.items.single.roomId, '123456789012');
      expect(result.hasMore, isFalse);
    },
  );

  test('blank search does not issue network requests', () async {
    HttpClient.instance.dio.httpClientAdapter = _Adapter(
      (_) => fail('Blank search should not make a request'),
    );
    expect((await DouyinSite().searchRooms('  ')).items, isEmpty);
    expect((await DouyinSite().searchAnchors('')).items, isEmpty);
  });

  test(
    'preserves complete cookie and keyword without preflight HEAD',
    () async {
      HttpClient.instance.dio.httpClientAdapter = _Adapter((request) {
        expect(request.method, 'GET');
        expect(request.uri.path, '/aweme/v1/web/live/search/');
        expect(request.headers['cookie'], 'sessionid=fake; ttwid=test');
        expect(request.uri.queryParameters['keyword'], '主播 & room');
        expect(request.uri.queryParameters['offset'], '10');
        expect(request.headers['referer'], contains('%26'));
        return {
          'status_code': 0,
          'has_more': 1,
          'data': [_live()],
        };
      });
      final result = await (DouyinSite()..cookie = 'sessionid=fake; ttwid=test')
          .searchRooms(' 主播 & room ', page: 2);
      expect(result.items.single.title, 'room');
      expect(result.items.single.online, 123);
      expect(result.hasMore, isTrue);
    },
  );

  test(
    'anonymous search retains default cookie and exposes login requirement',
    () async {
      HttpClient.instance.dio.httpClientAdapter = _Adapter((request) {
        expect(request.headers['cookie'], DouyinSite.kDefaultCookie);
        return {'status_code': 2483, 'status_msg': '请先登录，再继续搜索吧'};
      });
      await expectLater(
        DouyinSite().searchRooms('name'),
        throwsA(predicate((e) => e.toString().contains('需要登录'))),
      );
      await expectLater(
        DouyinSite().searchAnchors('name'),
        throwsA(predicate((e) => e.toString().contains('需要登录'))),
      );
    },
  );

  test('normal empty results remain empty, not a login error', () async {
    HttpClient.instance.dio.httpClientAdapter = _Adapter(
      (_) => {'status_code': 0, 'has_more': 0, 'data': []},
    );
    final result = await DouyinSite().searchRooms('no match');
    expect(result.items, isEmpty);
    expect(result.hasMore, isFalse);
  });

  test('server pagination flag takes priority over result count', () async {
    HttpClient.instance.dio.httpClientAdapter = _Adapter(
      (_) => {
        'data': List.generate(10, (i) => _live(id: '${1000 + i}')),
        'has_more': '0',
      },
    );
    final result = await DouyinSite().searchRooms('name');
    expect(result.items, hasLength(10));
    expect(result.hasMore, isFalse);
  });

  test(
    'parses live anchors and tolerates malformed or duplicate entries',
    () async {
      HttpClient.instance.dio.httpClientAdapter = _Adapter(
        (_) => {
          'data': [
            null,
            {},
            {'lives': 'invalid'},
            {
              'lives': {'rawdata': 'invalid json'},
            },
            _live(),
            _live(encoded: false),
            _live(encoded: false, id: '87654321'),
          ],
          'has_more': false,
        },
      );
      final result = await DouyinSite().searchAnchors('anchor');
      expect(result.items, hasLength(2));
      expect(result.items.first.avatar, 'avatar');
      expect(result.items.first.userName, 'anchor');
      expect(result.items.first.liveStatus, isTrue);
      expect(result.hasMore, isFalse);
    },
  );

  for (final response in <Object?>[
    '',
    'blocked',
    '<html>verification</html>',
    [],
    null,
    {'status_code': 5, 'data': []},
    {'status_code': '2483', 'data': []},
    {'status_code': 0},
    {'data': {}},
    {
      'data': [{}],
    },
  ]) {
    test(
      'invalid/restricted response is actionable: ${jsonEncode(response)}',
      () async {
        HttpClient.instance.dio.httpClientAdapter = _Adapter((_) => response);
        await expectLater(
          DouyinSite().searchRooms('name'),
          throwsA(predicate((e) => e.toString().contains('网页搜索'))),
        );
      },
    );
  }
}
