import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher_string.dart';

class DouyinSearchController extends BaseController {
  InAppWebViewController? webViewController;

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
  }

  final String keyword;
  final Site site;
  DouyinSearchController(this.site, {required this.keyword});

  String get searchUrl => keyword.trim().isEmpty
      ? "https://www.douyin.com/"
      : "https://www.douyin.com/search/${Uri.encodeComponent(keyword.trim())}?type=live";

  void onLoadStop(InAppWebViewController controller, Uri? uri) async {
    if (!isClosed) pageLoadding.value = false;
  }

  void onLoadStart(InAppWebViewController controller, Uri? uri) async {
    if (!isClosed) pageLoadding.value = true;
  }

  bool openRoom(Uri? uri) {
    if (isClosed || uri == null) return false;
    final roomId = DouyinSite.parseRoomId(uri.toString());
    if (roomId == null) return false;
    AppNavigator.toLiveRoomDetail(site: site, roomId: roomId);
    return true;
  }

  Future<bool?> onCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction createWindowAction,
  ) async {
    final uri = createWindowAction.request.url;
    if (!openRoom(uri) &&
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http')) {
      await controller.loadUrl(urlRequest: URLRequest(url: uri));
    }
    return false;
  }

  Future<void> saveLogin() async {
    if (loadding) return;
    loadding = true;
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri('https://www.douyin.com/'),
      );
      if (isClosed) return;
      final loggedIn = cookies.any(
        (cookie) =>
            (cookie.name == 'sessionid' || cookie.name == 'sessionid_ss') &&
            cookie.value.toString().isNotEmpty,
      );
      if (!loggedIn) {
        SmartDialog.showToast("请先在网页中登录抖音，再点击保存");
        return;
      }
      DouyinAccountService.instance.setCookie(
        cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; '),
      );
      Get.back(result: true);
    } catch (_) {
      SmartDialog.showToast("保存登录状态失败，可在账号管理中手动配置 Cookie");
    } finally {
      loadding = false;
    }
  }

  Future<void> openBrowser() async {
    try {
      final opened = await launchUrlString(
        searchUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) SmartDialog.showToast("无法打开浏览器");
    } catch (_) {
      SmartDialog.showToast("无法打开浏览器");
    }
  }

  @override
  void onClose() {
    webViewController = null;
    super.onClose();
  }
}
