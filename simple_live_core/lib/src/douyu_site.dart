import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/common/core_error.dart';
import 'package:simple_live_core/src/common/cookie_input.dart';
import 'package:simple_live_core/src/danmaku/douyu_danmaku.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/interface/live_site.dart';
import 'package:simple_live_core/src/model/live_anchor_item.dart';
import 'package:simple_live_core/src/model/live_category.dart';
import 'package:simple_live_core/src/model/live_message.dart';
import 'package:simple_live_core/src/model/live_play_url.dart';
import 'package:simple_live_core/src/model/live_room_item.dart';
import 'package:simple_live_core/src/model/live_search_result.dart';
import 'package:simple_live_core/src/model/live_room_detail.dart';
import 'package:simple_live_core/src/model/live_play_quality.dart';
import 'package:simple_live_core/src/model/live_category_result.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:simple_live_core/src/scripts/douyu_sign.dart';

class DouyuSite implements LiveSite {
  /// Optional Cookie header or Netscape file; anonymous requests use a distinct device.
  String cookie = '';
  String deviceId = '';
  static final String _processDeviceId = List.generate(
    32,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();

  String _cookieHeader(String url) =>
      CookieInput.headerFor(cookie, Uri.parse(url));

  String _cookieValue(String header, String key) {
    for (final part in header.split(';')) {
      final separator = part.indexOf('=');
      if (separator >= 0 && part.substring(0, separator).trim() == key) {
        return part.substring(separator + 1).trim();
      }
    }
    return '';
  }

  String _deviceDid(String? roomId, {String? url}) {
    final fromCookie = _cookieValue(
      _cookieHeader(
        url ?? 'https://www.douyu.com/lapi/live/getH5Play/${roomId ?? ''}',
      ),
      'acf_did',
    );
    return fromCookie.isNotEmpty
        ? fromCookie
        : deviceId.isNotEmpty
        ? deviceId
        : _processDeviceId;
  }

  Map<String, String> _requestHeaders(String? roomId, {String? url}) {
    final target =
        url ?? 'https://www.douyu.com/lapi/live/getH5Play/${roomId ?? ''}';
    final header = _cookieHeader(target);
    final did = _deviceDid(roomId, url: target);
    final cookies = <String>[
      if (header.isNotEmpty) header,
      if (_cookieValue(header, 'dy_did').isEmpty) 'dy_did=$did',
      if (_cookieValue(header, 'acf_did').isEmpty) 'acf_did=$did',
    ];
    return {
      'referer': 'https://www.douyu.com/${roomId ?? ''}',
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
      'cookie': cookies.join('; '),
    };
  }

  @override
  String id = "douyu";

  @override
  String name = "斗鱼直播";

  @override
  LiveDanmaku getDanmaku() => DouyuDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async {
    List<LiveCategory> categories = [];
    var result = await HttpClient.instance.getJson(
      "https://m.douyu.com/api/cate/list",
    );
    var subCateList = result["data"]["cate2Info"] as List;
    for (var item in result["data"]["cate1Info"]) {
      var cate1Id = item["cate1Id"];
      var cate1Name = item["cate1Name"];
      List<LiveSubCategory> subCategories = [];
      subCateList.where((x) => x["cate1Id"] == cate1Id).forEach((element) {
        subCategories.add(
          LiveSubCategory(
            pic: element["icon"],
            id: element["cate2Id"].toString(),
            parentId: cate1Id.toString(),
            name: element["cate2Name"].toString(),
          ),
        );
      });
      categories.add(
        LiveCategory(
          id: cate1Id.toString(),
          name: cate1Name.toString(),
          children: subCategories,
        ),
      );
    }
    // 根据ID排序
    categories.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));

    return categories;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/gapi/rkc/directory/mixList/2_${category.id}/$page",
      queryParameters: {},
    );

    var items = <LiveRoomItem>[];
    for (var item in result['data']['rl']) {
      if (item["type"] != 1) {
        continue;
      }
      var roomItem = LiveRoomItem(
        cover: item['rs16'].toString(),
        online: item['ol'],
        roomId: item['rid'].toString(),
        title: item['rn'].toString(),
        userName: item['nn'].toString(),
      );
      items.add(roomItem);
    }
    var hasMore = page < result['data']['pgcnt'];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async {
    // Account/device identity can change while the room remains open.
    var data = await getPlayArgs(detail.roomId);
    data += "&cdn=&rate=-1&ver=Douyu_223061205&iar=0&ive=0&hevc=0&fa=0";
    List<LivePlayQuality> qualities = [];
    var result = await HttpClient.instance.postJson(
      "https://www.douyu.com/lapi/live/getH5Play/${detail.roomId}",
      data: data,
      header: _requestHeaders(detail.roomId),
      formUrlEncoded: true,
    );

    final payload = result is Map ? result['data'] : null;
    if (result is! Map ||
        result['error']?.toString() != '0' ||
        payload is! Map ||
        payload['cdnsWithName'] is! List ||
        payload['multirates'] is! List) {
      throw CoreError(
        '斗鱼播放清晰度读取失败：${result is Map ? result['msg'] ?? result['error'] : '无效响应'}',
      );
    }
    var cdns = <String>[];
    for (var item in payload["cdnsWithName"]) {
      cdns.add(item["cdn"].toString());
    }

    // 如果cdn以scdn开头，将其放到最后
    cdns.sort((a, b) {
      if (a.startsWith("scdn") && !b.startsWith("scdn")) {
        return 1;
      } else if (!a.startsWith("scdn") && b.startsWith("scdn")) {
        return -1;
      }
      return 0;
    });

    for (var item in payload["multirates"]) {
      qualities.add(
        LivePlayQuality(
          quality: item["name"].toString(),
          data: DouyuPlayData(item["rate"], cdns),
        ),
      );
    }
    return qualities;
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    // Sign again when selecting a quality: the room's initial signature may
    // already have expired after watching for several minutes.
    final args = await getPlayArgs(detail.roomId);
    final data = quality.data as DouyuPlayData;
    Object? firstError;
    final routes = await Future.wait(
      data.cdns.map((cdn) async {
        try {
          return await _getPlayRoute(detail.roomId, args, data.rate, cdn);
        } catch (error) {
          firstError ??= error;
          return null;
        }
      }),
    );
    final available = <_DouyuPlayRoute>[];
    final seen = <String>{};
    for (final route in routes) {
      if (route != null && seen.add(route.url)) available.add(route);
    }
    if (available.isEmpty) {
      throw firstError ?? CoreError('斗鱼没有可用的播放线路');
    }
    // Prefer a CDN that honors the requested quality, keeping the original
    // CDN order within each group. Other working routes remain available.
    final ordered = [
      ...available.where((r) => r.rate == data.rate),
      ...available.where((r) => r.rate != data.rate),
    ];
    return LivePlayUrl(
      urls: ordered.map((r) => r.url).toList(),
      qualities: ordered.map((r) => r.quality).toList(),
      headers: {
        'referer': 'https://www.douyu.com/${detail.roomId}',
        'user-agent': _requestHeaders(detail.roomId)['user-agent']!,
      },
    );
  }

  Future<String> getPlayUrl(
    String roomId,
    String args,
    int rate,
    String cdn,
  ) async => (await _getPlayRoute(roomId, args, rate, cdn)).url;

  Future<_DouyuPlayRoute> _getPlayRoute(
    String roomId,
    String args,
    int rate,
    String cdn,
  ) async {
    // ive=1 can force an adaptive 540p/25fps stream despite rate=0. fa=1
    // returns an audio-only stream, so always keep it disabled for video.
    args += "&cdn=$cdn&rate=$rate&ver=Douyu_223061205&iar=0&ive=0&hevc=0&fa=0";
    final result = await HttpClient.instance.postJson(
      "https://www.douyu.com/lapi/live/getH5Play/$roomId",
      data: args,
      header: _requestHeaders(roomId),
      formUrlEncoded: true,
    );
    if (result is! Map || result['error']?.toString() != '0') {
      throw CoreError(
        '斗鱼播放地址请求失败：${result is Map ? result['msg'] ?? result['error'] : '无效响应'}',
      );
    }
    final payload = result['data'];
    if (payload is! Map ||
        payload['rtmp_url'] is! String ||
        (payload['rtmp_url'] as String).isEmpty ||
        payload['rtmp_live'] is! String ||
        (payload['rtmp_live'] as String).isEmpty) {
      throw CoreError('斗鱼返回了无效的播放地址');
    }
    final actualRate = int.tryParse(payload['rate']?.toString() ?? '');
    var actualQuality = '';
    for (final entry in payload['multirates'] as List? ?? const []) {
      if (actualRate != null &&
          int.tryParse(entry['rate']?.toString() ?? '') == actualRate) {
        actualQuality = entry['name']?.toString() ?? '';
        break;
      }
    }
    return _DouyuPlayRoute(
      "${payload['rtmp_url']}/${HtmlUnescape().convert(payload['rtmp_live'])}",
      actualRate,
      actualQuality,
    );
  }

  Future<String> getPlayArgs(String roomId) async {
    final encoded = await HttpClient.instance.getText(
      'https://www.douyu.com/swf_api/homeH5Enc?rids=$roomId',
      header: _requestHeaders(
        roomId,
        url: 'https://www.douyu.com/swf_api/homeH5Enc',
      ),
    );
    final decoded = json.decode(encoded);
    final payload = decoded is Map ? decoded['data'] : null;
    final script = payload is Map ? payload['room$roomId'] : null;
    if (script is! String || script.isEmpty) {
      throw CoreError('斗鱼播放签名读取失败');
    }
    return DouyuSign.getSign(script, roomId, _deviceDid(roomId));
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/weblist/apinc/allpage/6/$page",
      queryParameters: {},
    );

    var items = <LiveRoomItem>[];
    for (var item in result['data']['rl']) {
      if (item["type"] != 1) {
        continue;
      }
      var roomItem = LiveRoomItem(
        cover: item['rs16'].toString(),
        online: item['ol'],
        roomId: item['rid'].toString(),
        title: item['rn'].toString(),
        userName: item['nn'].toString(),
      );
      items.add(roomItem);
    }
    var hasMore = page < result['data']['pgcnt'];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    Map roomInfo = await _getRoomInfo(roomId);

    Map h5RoomInfo = await HttpClient.instance.getJson(
      "https://www.douyu.com/swf_api/h5room/$roomId",
      queryParameters: {},
      header: _requestHeaders(
        roomId,
        url: 'https://www.douyu.com/swf_api/h5room/$roomId',
      ),
    );
    String? showTime = h5RoomInfo["data"]?["show_time"]?.toString();

    if (showTime != null && showTime.isNotEmpty) {
      try {
        int startTimeStamp = int.parse(showTime);
        int currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        int durationInSeconds = currentTimeStamp - startTimeStamp;

        int hours = durationInSeconds ~/ 3600;
        int minutes = (durationInSeconds % 3600) ~/ 60;
        int seconds = durationInSeconds % 60;

        String formattedDuration =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        print('斗鱼直播间 $roomId 开播时长: $formattedDuration');
      } catch (e) {
        print('计算开播时长出错: $e');
      }
    }

    return LiveRoomDetail(
      cover: roomInfo["room_pic"].toString(),
      online: int.tryParse(roomInfo["room_biz_all"]["hot"].toString()) ?? 0,
      roomId: roomInfo["room_id"].toString(),
      title: roomInfo["room_name"].toString(),
      userName: roomInfo["owner_name"].toString(),
      userAvatar: roomInfo["owner_avatar"].toString(),
      introduction: roomInfo["show_details"].toString(),
      notice: "",
      status: roomInfo["show_status"] == 1 && roomInfo["videoLoop"] != 1,
      danmakuData: roomInfo["room_id"].toString(),
      data: await getPlayArgs(roomInfo["room_id"].toString()),
      url: "https://www.douyu.com/$roomId",
      isRecord: roomInfo["videoLoop"] == 1,
      showTime: showTime,
    );
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
  }) async {
    var did = generateRandomString(32);
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/search/api/searchShow",
      queryParameters: {"kw": keyword, "page": page, "pageSize": 20},
      header: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51',
        'referer': 'https://www.douyu.com/search/',
        'Cookie': 'dy_did=$did;acf_did=$did',
      },
    );
    if (result['error'] != 0) {
      throw Exception(result['msg']);
    }
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["relateShow"]) {
      var roomItem = LiveRoomItem(
        roomId: item["rid"].toString(),
        title: item["roomName"].toString(),
        cover: item["roomSrc"].toString(),
        userName: item["nickName"].toString(),
        online: parseHotNum(item["hot"].toString()),
      );
      items.add(roomItem);
    }
    var hasMore = result["data"]["relateShow"].isNotEmpty;
    return LiveSearchRoomResult(hasMore: hasMore, items: items);
  }

  Future<Map> _getRoomInfo(String roomId) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/betard/$roomId",
      queryParameters: {},
      header: _requestHeaders(
        roomId,
        url: 'https://www.douyu.com/betard/$roomId',
      ),
    );
    Map roomInfo;
    if (result is String) {
      roomInfo = json.decode(result)["room"];
    } else {
      roomInfo = result["room"];
    }
    return roomInfo;
  }

  //生成指定长度的16进制随机字符串
  String generateRandomString(int length) {
    var random = Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(16));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item.toRadixString(16));
    }
    return stringBuffer.toString();
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
  }) async {
    var did = generateRandomString(32);
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/search/api/searchUser",
      queryParameters: {
        "kw": keyword,
        "page": page,
        "pageSize": 20,
        "filterType": 1,
      },
      header: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51',
        'referer': 'https://www.douyu.com/search/',
        'Cookie': 'dy_did=$did;acf_did=$did',
      },
    );

    var items = <LiveAnchorItem>[];
    for (var item in result["data"]["relateUser"]) {
      var liveStatus =
          (int.tryParse(item["anchorInfo"]["isLive"].toString()) ?? 0) == 1;
      var roomType =
          (int.tryParse(item["anchorInfo"]["roomType"].toString()) ?? 0);
      var roomItem = LiveAnchorItem(
        roomId: item["anchorInfo"]["rid"].toString(),
        avatar: item["anchorInfo"]["avatar"].toString(),
        userName: item["anchorInfo"]["nickName"].toString(),
        liveStatus: liveStatus && roomType == 0,
      );
      items.add(roomItem);
    }
    var hasMore = result["data"]["relateUser"].isNotEmpty;
    return LiveSearchAnchorResult(hasMore: hasMore, items: items);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    var roomInfo = await _getRoomInfo(roomId);
    return roomInfo["show_status"] == 1 && roomInfo["videoLoop"] != 1;
  }

  int parseHotNum(String hn) {
    try {
      var num = double.parse(hn.replaceAll("万", ""));
      if (hn.contains("万")) {
        num *= 10000;
      }
      return num.round();
    } catch (_) {
      return -999;
    }
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({
    required String roomId,
  }) {
    //尚不支持
    return Future.value([]);
  }
}

class DouyuPlayData {
  final int rate;
  final List<String> cdns;
  DouyuPlayData(this.rate, this.cdns);
}

class _DouyuPlayRoute {
  final String url;
  final int? rate;
  final String quality;
  const _DouyuPlayRoute(this.url, this.rate, this.quality);
}
