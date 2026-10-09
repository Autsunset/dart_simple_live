import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyinAccountService extends GetxService {
  static DouyinAccountService get instance => Get.find<DouyinAccountService>();

  var cookie = "";
  var hasCookie = false.obs;

  @override
  void onInit() {
    final saved = LocalStorageService.instance.getValue(
      LocalStorageService.kDouyinCookie,
      "",
    );
    cookie = validateCookie(saved) == null ? normalizeCookie(saved) : '';
    hasCookie.value = cookie.isNotEmpty;
    setSite();
    super.onInit();
  }

  void setSite() {
    var site = (Sites.allSites[Constant.kDouyin]!.liveSite as DouyinSite);
    site.cookie = cookie;
  }

  static String normalizeCookie(String input) {
    if (CookieInput.isNetscape(input)) {
      return CookieInput.normalizeForStorage(input, domain: 'douyin.com');
    }
    final value = input
        .trim()
        .replaceFirst(RegExp(r'^cookie:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    if (value.isEmpty) return '';
    return CookieInput.normalizeForStorage(
      value.contains('=') ? value : 'ttwid=$value',
      domain: 'douyin.com',
    );
  }

  static String? validateCookie(String input) {
    try {
      final value = normalizeCookie(input);
      if (value.isEmpty) return null;
      final applicable = [
        'https://live.douyin.com/webcast/room/web/enter/',
        'https://www.douyin.com/aweme/v1/web/live/search/',
      ].any((url) => CookieInput.headerFor(value, Uri.parse(url)).isNotEmpty);
      return applicable ? null : '文件没有适用于抖音直播接口的 Cookie，请重新导出';
    } on FormatException catch (error) {
      return error.message;
    }
  }

  Future<void> setCookie(String input) async {
    final error = validateCookie(input);
    if (error != null) throw ArgumentError(error);
    final value = normalizeCookie(input);
    await LocalStorageService.instance.setValue(
      LocalStorageService.kDouyinCookie,
      value,
    );
    cookie = value;
    hasCookie.value = cookie.isNotEmpty;
    setSite();
  }

  Future<void> clearCookie() => setCookie('');
}
