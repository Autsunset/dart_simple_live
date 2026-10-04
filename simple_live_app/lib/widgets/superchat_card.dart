import 'dart:async';

import 'package:flutter/material.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_core/simple_live_core.dart';

class SuperChatCard extends StatefulWidget {
  final LiveSuperChatMessage message;
  final Function()? onExpire;
  final int? customCountdown;
  const SuperChatCard(
    this.message, {
    required this.onExpire,
    this.customCountdown,
    Key? key,
  }) : super(key: key);

  @override
  State<SuperChatCard> createState() => _SuperChatCardState();
}

class _SuperChatCardState extends State<SuperChatCard> {
  Timer? timer;

  int countdown = 0;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  int _remaining() => widget.message.endTime
      .difference(DateTime.now())
      .inSeconds
      .clamp(0, 86400);

  void _startCountdown() {
    timer?.cancel();
    countdown = _remaining();
    // An overlay supplies its own timer and shorter display duration.
    if (widget.customCountdown != null) return;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => countdown = _remaining());
      if (countdown <= 0) {
        timer?.cancel();
        widget.onExpire?.call();
      }
    });
  }

  @override
  void didUpdateWidget(covariant SuperChatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.endTime != widget.message.endTime ||
        oldWidget.customCountdown != widget.customCountdown) {
      _startCountdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayCountdown = widget.customCountdown ?? countdown;
    return ClipRRect(
      borderRadius: AppStyle.radius8,
      child: Container(
        decoration: BoxDecoration(
          color: Utils.convertHexColor(widget.message.backgroundColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: AppStyle.edgeInsetsA8,
              child: Row(
                children: [
                  NetImage(
                    widget.message.face,
                    width: 48,
                    height: 48,
                    borderRadius: 36,
                  ),
                  AppStyle.hGap12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.message.userName,
                          style: const TextStyle(
                            color: AppColors.black333,
                          ),
                        ),
                        Text(
                          "￥${widget.message.price}",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    "$displayCountdown",
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color:
                    Utils.convertHexColor(widget.message.backgroundBottomColor),
              ),
              padding: AppStyle.edgeInsetsA8,
              child: Text(
                widget.message.message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
}
