import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/search/douyin/douyin_search_controller.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyinSearchView extends GetView<DouyinSearchController> {
  const DouyinSearchView({super.key});

  @override
  Widget build(BuildContext context) {
    final hasWebView = Platform.isAndroid || Platform.isIOS;
    return Scaffold(
      appBar: AppBar(
        title: const Text("抖音网页搜索"),
        actions: [
          IconButton(
            tooltip: "在浏览器中打开",
            onPressed: controller.openBrowser,
            icon: const Icon(Icons.open_in_browser),
          ),
          if (hasWebView)
            TextButton(
              onPressed: controller.saveLogin,
              child: const Text("保存登录"),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Text(
              hasWebView
                  ? "在抖音官网完成登录后，点击「保存登录」重试搜索；"
                        "也可直接点击网页中的直播间。登录凭据保存在应用设置中，请勿分享 Cookie 或备份文件。"
                  : "请在浏览器中登录并搜索，复制直播间链接回到搜索框，"
                        "或在账号管理中配置完整 Cookie。",
            ),
          ),
          if (hasWebView)
            Obx(
              () => controller.pageLoadding.value
                  ? const LinearProgressIndicator()
                  : const SizedBox(height: 4),
            ),
          Expanded(
            child: hasWebView
                ? InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(controller.searchUrl),
                    ),
                    onWebViewCreated: controller.onWebViewCreated,
                    onLoadStart: controller.onLoadStart,
                    onLoadStop: controller.onLoadStop,
                    onReceivedError: (_, request, error) {
                      if (request.isForMainFrame == true &&
                          !controller.isClosed) {
                        controller.pageLoadding.value = false;
                      }
                    },
                    initialSettings: InAppWebViewSettings(
                      userAgent: DouyinSite.kDefaultUserAgent,
                      useShouldOverrideUrlLoading: true,
                      // Keep target=_blank navigation in this WebView so room
                      // links are intercepted even when Android omits the URL.
                      supportMultipleWindows: false,
                      javaScriptCanOpenWindowsAutomatically: true,
                    ),
                    onCreateWindow: controller.onCreateWindow,
                    shouldOverrideUrlLoading: (_, action) async {
                      if (action.isForMainFrame &&
                          controller.openRoom(action.request.url)) {
                        return NavigationActionPolicy.CANCEL;
                      }
                      final scheme = action.request.url?.scheme;
                      if (scheme != null &&
                          scheme != 'http' &&
                          scheme != 'https' &&
                          scheme != 'about') {
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.ALLOW;
                    },
                  )
                : Center(
                    child: Wrap(
                      spacing: 12,
                      children: [
                        TextButton.icon(
                          onPressed: controller.openBrowser,
                          icon: const Icon(Icons.open_in_browser),
                          label: const Text("打开浏览器搜索"),
                        ),
                        TextButton(
                          onPressed: () =>
                              Get.toNamed(RoutePath.kSettingsAccount),
                          child: const Text("配置 Cookie"),
                        ),
                        TextButton(
                          onPressed: () => Get.toNamed(RoutePath.kTools),
                          child: const Text("解析直播链接"),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
