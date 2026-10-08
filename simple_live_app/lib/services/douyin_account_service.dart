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
    cookie = LocalStorageService.instance.getValue(
      LocalStorageService.kDouyinCookie,
      "",
    );
    hasCookie.value = cookie.isNotEmpty;
    setSite();
    super.onInit();
  }

  void setSite() {
    var site = (Sites.allSites[Constant.kDouyin]!.liveSite as DouyinSite);
    site.cookie = cookie;
  }

  static String normalizeCookie(String input) {
    final value = input
        .trim()
        .replaceFirst(RegExp(r'^cookie:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    if (value.isEmpty) return '';
    // Keep complete browser cookies intact while accepting legacy ttwid values.
    return value.contains('=') ? value : 'ttwid=$value';
  }

  void setCookie(String input) {
    cookie = normalizeCookie(input);
    LocalStorageService.instance.setValue(
      LocalStorageService.kDouyinCookie,
      cookie,
    );
    hasCookie.value = cookie.isNotEmpty;
    setSite();
  }

  void clearCookie() {
    cookie = "";
    LocalStorageService.instance.setValue(
      LocalStorageService.kDouyinCookie,
      "",
    );
    hasCookie.value = false;
    setSite();
  }
}
