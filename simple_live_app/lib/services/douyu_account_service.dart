import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyuAccountService extends GetxService {
  static DouyuAccountService get instance => Get.find<DouyuAccountService>();

  String cookie = '';
  final hasCookie = false.obs;

  @override
  void onInit() {
    final saved = LocalStorageService.instance.getValue(
      LocalStorageService.kDouyuCookie,
      '',
    );
    cookie = validateCookie(saved) == null ? normalizeCookie(saved) : '';
    _setSite();
    super.onInit();
  }

  static String normalizeCookie(String input) {
    return input
        .trim()
        .replaceFirst(RegExp(r'^cookie:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .split(';')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join('; ');
  }

  static String? validateCookie(String input) {
    final value = normalizeCookie(input);
    if (value.isEmpty) return null;
    var hasDevice = false;
    for (final part in value.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) return '请粘贴完整 Cookie，不是网址或单独的设备 ID';
      final name = part.substring(0, separator).trim();
      if (!RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$").hasMatch(name)) {
        return 'Cookie 格式不正确，请复制请求头中的 Cookie 值';
      }
      if (name == 'acf_did' &&
          part.substring(separator + 1).trim().isNotEmpty) {
        hasDevice = true;
      }
    }
    return hasDevice ? null : 'Cookie 缺少 acf_did，请复制本人登录后的完整 Cookie';
  }

  Future<void> setCookie(String input) async {
    final error = validateCookie(input);
    if (error != null) throw ArgumentError(error);
    final value = normalizeCookie(input);
    // Do not replace a working session if persisting the new value fails.
    await LocalStorageService.instance.setValue(
      LocalStorageService.kDouyuCookie,
      value,
    );
    cookie = value;
    _setSite();
  }

  Future<void> clearCookie() => setCookie('');

  void _setSite() {
    (Sites.allSites[Constant.kDouyu]!.liveSite as DouyuSite).cookie = cookie;
    hasCookie.value = cookie.isNotEmpty;
  }
}
