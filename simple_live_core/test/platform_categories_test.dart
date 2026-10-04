import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

class _Bili extends BiliBiliSite {
  @override
  Future<Map<String, String>> getHeader() async => {};
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Object Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    final body = respond(request);
    return ResponseBody.fromString(
      body is String ? body : jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpClientAdapter original;
  setUp(() => original = HttpClient.instance.dio.httpClientAdapter);
  tearDown(() => HttpClient.instance.dio.httpClientAdapter = original);
  test('Bili categories paginate and fall back to user cover', () async {
    HttpClient.instance.dio.httpClientAdapter = _Adapter((request) {
      expect(request.uri.path, '/room/v1/Area/getRoomList');
      expect(request.queryParameters['page'], 2);
      return {
        'code': 0,
        'data': List.generate(
          30,
          (i) => {
            'roomid': i,
            'title': 'room',
            'uname': 'user',
            'online': '100',
            'user_cover': 'https://example.invalid/cover',
          },
        ),
      };
    });
    final response = await _Bili().getCategoryRooms(
      LiveSubCategory(id: '1', name: 'category', parentId: '2', pic: ''),
      page: 2,
    );
    expect(response.hasMore, isTrue);
    expect(
      response.items.first.cover,
      'https://example.invalid/cover@400w.jpg',
    );
  });
  test('Bili blocked response is reported without a null reference', () async {
    HttpClient.instance.dio.httpClientAdapter = _Adapter(
      (_) => {'code': -352, 'message': 'blocked', 'data': null},
    );
    await expectLater(
      _Bili().getCategoryRooms(
        LiveSubCategory(id: '1', name: '', parentId: '2', pic: ''),
      ),
      throwsA(predicate((e) => e.toString().contains('blocked'))),
    );
  });
  test('Douyin game grandchildren remain selectable with unique ids', () async {
    Map<String, dynamic> partition(
      String id,
      String title, [
      List children = const [],
    ]) => {
      'partition': {'id_str': id, 'type': 1, 'title': title},
      'sub_partition': children,
    };
    final categories = [
      partition('1', '游戏', [
        partition('2', '网游', [partition('3', '英雄联盟'), partition('3', '英雄联盟')]),
      ]),
    ];
    final flight = jsonEncode({'categoryData': categories});
    HttpClient.instance.dio.httpClientAdapter = _Adapter(
      (_) => '<script>self.__next_f.push([1,${jsonEncode(flight)}])</script>',
    );
    final response = await DouyinSite().getCategores();
    expect(response.single.children.map((c) => c.id), ['1,1', '2,1', '3,1']);
    expect(response.single.children.last.name, '英雄联盟');
  });
  test('Douyin search preserves the configured cookie', () async {
    var requested = false;
    HttpClient.instance.dio.httpClientAdapter = _Adapter((request) {
      if (request.method == 'HEAD') return '';
      expect(request.headers['cookie'], 'test-session=123');
      requested = true;
      return {'data': []};
    });
    await (DouyinSite()..cookie = 'test-session=123').searchRooms('test');
    expect(requested, isTrue);
  });
}
