import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/desktop_refresh_button.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:simple_live_app/widgets/net_image.dart';

/// Shared by the portrait sheet and landscape/desktop side panel (PR #881).
class RoomQuickSwitch extends StatefulWidget {
  final LiveRoomController controller;
  final VoidCallback close;

  const RoomQuickSwitch({
    required this.controller,
    required this.close,
    super.key,
  });

  @override
  State<RoomQuickSwitch> createState() => _RoomQuickSwitchState();
}

class _RoomQuickSwitchState extends State<RoomQuickSwitch>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final List<History> _history;

  @override
  void initState() {
    super.initState();
    _tabs =
        TabController(
          length: 2,
          vsync: this,
          initialIndex: widget.controller.quickSwitchTab.value,
        )..addListener(() {
          widget.controller.quickSwitchTab.value = _tabs.index;
        });
    // Sort/read once per opening, rather than on each reactive list update.
    _history = DBService.instance
        .getHistores()
        .where((item) => Sites.allSites.containsKey(item.siteId))
        .toList();
  }

  void _select(String siteId, String roomId) {
    if (widget.controller.roomClosed) return;
    final site = Sites.allSites[siteId];
    if (site == null) return;
    widget.close();
    widget.controller.resetRoom(site, roomId);
  }

  Widget _follows() => Obx(() {
    final service = FollowService.instance;
    final items = service.liveList
        .where((item) => Sites.allSites.containsKey(item.siteId))
        .toList();
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: service.loadData,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              return Obx(
                () => FollowUserItem(
                  key: ValueKey(item.id),
                  item: item,
                  playing:
                      widget.controller.site.id == item.siteId &&
                      widget.controller.roomId == item.roomId,
                  onTap: () => _select(item.siteId, item.roomId),
                ),
              );
            },
          ),
        ),
        if (items.isEmpty)
          const IgnorePointer(child: Center(child: Text('暂无正在直播的关注'))),
        if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
          Positioned(
            right: 12,
            bottom: 12,
            child: Obx(
              () => DesktopRefreshButton(
                refreshing: service.updating.value,
                onPressed: service.loadData,
              ),
            ),
          ),
      ],
    );
  });

  Widget _histories() {
    if (_history.isEmpty) return const Center(child: Text('暂无观看历史'));
    return ListView.builder(
      itemCount: _history.length,
      itemBuilder: (_, i) {
        final item = _history[i];
        final site = Sites.allSites[item.siteId]!;
        return Obx(() {
          final playing =
              widget.controller.site.id == item.siteId &&
              widget.controller.roomId == item.roomId;
          return ListTile(
            key: ValueKey(item.id),
            leading: NetImage(
              item.face,
              width: 48,
              height: 48,
              borderRadius: 24,
            ),
            title: Text(
              item.userName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Wrap(
              spacing: 8,
              children: [
                Image.asset(site.logo, width: 20),
                Text(site.name),
                Text(Utils.parseTime(item.updateTime)),
              ],
            ),
            selected: playing,
            trailing: playing ? const Icon(Icons.play_arrow) : null,
            onTap: () => _select(item.siteId, item.roomId),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: '关注列表'),
          Tab(text: '观看历史'),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [_follows(), _histories()],
        ),
      ),
    ],
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }
}
