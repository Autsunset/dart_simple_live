import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyinRoomEntryDialog extends StatefulWidget {
  final String initialValue;

  const DouyinRoomEntryDialog({super.key, this.initialValue = ''});

  @override
  State<DouyinRoomEntryDialog> createState() => _DouyinRoomEntryDialogState();
}

class _DouyinRoomEntryDialogState extends State<DouyinRoomEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _input = TextEditingController(text: widget.initialValue);

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Get.back(result: DouyinSite.parseRoomId(_input.text));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('抖音房间号进入'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '输入 live.douyin.com/ 后面的数字，或粘贴完整直播间链接。'
                '直接打开播放器，不经过关键词搜索。\n'
                '默认使用内置 ttwid；直播房间号不是账号的抖音号。',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _input,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                decoration: const InputDecoration(
                  labelText: '直播房间号或完整链接',
                  border: OutlineInputBorder(),
                  errorMaxLines: 2,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入直播房间号或完整链接';
                  }
                  if (DouyinSite.parseRoomId(value) == null) {
                    return '请输入数字房间号或支持的抖音直播间链接';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('取消')),
        TextButton(onPressed: _submit, child: const Text('进入直播间')),
      ],
    );
  }
}
