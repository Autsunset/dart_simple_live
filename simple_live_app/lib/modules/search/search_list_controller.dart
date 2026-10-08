import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/search/douyin/douyin_search_controller.dart';
import 'package:simple_live_app/modules/search/douyin/douyin_search_view.dart';
import 'package:simple_live_app/routes/route_path.dart';

class SearchListController extends BasePageController {
  String keyword = "";

  /// 搜索模式，0=直播间，1=主播
  var searchMode = 0.obs;
  final Site site;
  SearchListController(this.site);

  Future<void> openDouyinWebSearch() async {
    final saved = await Get.to<bool>(
      () => const DouyinSearchView(),
      binding: BindingsBuilder.put(
        () => DouyinSearchController(site, keyword: keyword),
      ),
    );
    if (saved == true && !isClosed) await refreshData();
  }

  Future<void> configureDouyinCookie() async {
    await Get.toNamed(RoutePath.kSettingsAccount);
    if (!isClosed) await refreshData();
  }

  @override
  Future refreshData() async {
    if (keyword.isEmpty) {
      return;
    }
    return await super.refreshData();
  }

  @override
  Future<List> getData(int page, int pageSize) async {
    if (keyword.isEmpty) {
      return [];
    }
    if (searchMode.value == 1) {
      // 搜索主播
      var result = await site.liveSite.searchAnchors(keyword, page: page);
      return result.items;
    }
    var result = await site.liveSite.searchRooms(keyword, page: page);

    return result.items;
  }

  void clear() {
    pageEmpty.value = false;
    list.clear();
  }
}
