import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/scripts/douyu_sign.dart';
import 'package:test/test.dart';

class _Site extends DouyuSite {
  int signatures = 0;
  @override
  Future<String> getPlayArgs(String roomId) async =>
      'signature=${++signatures}';
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final gates = <String, Completer<void>>{};
  bool failAll = false;
  final returnedRates = <String, int>{};
  String? expectedCookie;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (expectedCookie != null) {
      expect(options.headers['cookie'], expectedCookie);
    }
    final args = Uri.splitQueryString(options.data as String);
    expect(args['iar'], '0');
    expect(args['ive'], '0');
    expect(args['fa'], '0');
    final cdn = args['cdn']!;
    final gate = gates[cdn];
    if (gate != null) await gate.future;
    final data = failAll || cdn == 'broken'
        ? {'error': 1, 'msg': 'unavailable'}
        : {
            'error': 0,
            'data': {
              'rate': returnedRates[cdn] ?? int.parse(args['rate']!),
              'multirates': [
                {'rate': 0, 'name': '原画1080P60'},
                {'rate': 3, 'name': '超清'},
                {'rate': 2, 'name': '高清'},
              ],
              'rtmp_url': 'https://$cdn.invalid',
              'rtmp_live': 'live.flv?rate=${args['rate']}&amp;token=ok',
            },
          };
    return ResponseBody.fromString(
      jsonEncode(data),
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
  late _Adapter adapter;
  late HttpClientAdapter original;
  final detail = LiveRoomDetail(
    roomId: '1',
    title: '',
    cover: '',
    userName: '',
    userAvatar: '',
    online: 0,
    status: true,
    url: '',
    data: 'expired-signature',
  );
  setUp(() {
    original = HttpClient.instance.dio.httpClientAdapter;
    adapter = _Adapter();
    HttpClient.instance.dio.httpClientAdapter = adapter;
  });
  tearDown(() => HttpClient.instance.dio.httpClientAdapter = original);

  test(
    'CDNs are concurrent, keep their order and survive one failed route',
    () async {
      final site = _Site();
      adapter.gates['first'] = Completer<void>();
      adapter.gates['last'] = Completer<void>();
      final response = site.getPlayUrls(
        detail: detail,
        quality: LivePlayQuality(
          quality: '1080P60',
          data: DouyuPlayData(3, ['first', 'broken', 'last']),
        ),
      );
      // If requests were serial, last would not begin until first completes.
      for (var i = 0; i < 20 && adapter.requests.length < 3; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(adapter.requests.length, 3);
      adapter.gates['last']!.complete();
      adapter.gates['first']!.complete();
      final result = await response;
      expect(result.urls.map((s) => Uri.parse(s).host), [
        'first.invalid',
        'last.invalid',
      ]);
      expect(result.urls.every((s) => s.contains('rate=3&token=ok')), isTrue);
      expect(site.signatures, 1);
      expect(
        adapter.requests.every(
          (r) => (r.data as String).contains('signature=1'),
        ),
        isTrue,
      );
    },
  );

  test(
    'each quality request signs again and all-route failure is surfaced',
    () async {
      final site = _Site();
      final quality = LivePlayQuality(
        quality: 'HD',
        data: DouyuPlayData(2, ['first']),
      );
      await site.getPlayUrls(detail: detail, quality: quality);
      await site.getPlayUrls(detail: detail, quality: quality);
      expect(site.signatures, 2);
      adapter.failAll = true;
      await expectLater(
        site.getPlayUrls(detail: detail, quality: quality),
        throwsA(anything),
      );
    },
  );
  test(
    'routes that honor requested quality come first and report actual names',
    () async {
      adapter.returnedRates['first'] = 2;
      adapter.returnedRates['last'] = 0;
      final result = await _Site().getPlayUrls(
        detail: detail,
        quality: LivePlayQuality(
          quality: '原画1080P60',
          data: DouyuPlayData(0, ['first', 'last']),
        ),
      );
      expect(result.urls.map((s) => Uri.parse(s).host), [
        'last.invalid',
        'first.invalid',
      ]);
      expect(result.qualities, ['原画1080P60', '高清']);
      expect(result.headers?['referer'], 'https://www.douyu.com/1');
      expect(result.headers?.containsKey('cookie'), isFalse);
    },
  );

  test(
    'account cookie device identity takes priority over injected fallback',
    () async {
      adapter.expectedCookie =
          'session=fake; acf_did=account-device; dy_did=account-device';
      await (_Site()
            ..cookie = 'session=fake; acf_did=account-device'
            ..deviceId = 'fallback-device')
          .getPlayUrls(
            detail: detail,
            quality: LivePlayQuality(
              quality: '高清',
              data: DouyuPlayData(2, ['first']),
            ),
          );
    },
  );

  test('signer forwards explicit identity and quotes arguments as data', () {
    const room = "1'\\quoted";
    const device = 'device"\\id';
    final result = DouyuSign.getSign(
      'function ub98484234(rid,did,time){return JSON.stringify([rid,did]);}',
      room,
      device,
    );
    expect(jsonDecode(result), [room, device]);
  });
}
