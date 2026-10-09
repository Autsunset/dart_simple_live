import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/widgets/cookie_file_import_button.dart';

class DouyinCookieDialog extends StatefulWidget {
  final String initialValue;

  const DouyinCookieDialog({super.key, required this.initialValue});

  @override
  State<DouyinCookieDialog> createState() => _DouyinCookieDialogState();
}

class _DouyinCookieDialogState extends State<DouyinCookieDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _input = TextEditingController(text: widget.initialValue);

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Get.back(result: DouyinAccountService.normalizeCookie(_input.text));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('配置抖音 ttwid'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '默认已内置 ttwid，公开直播间可以通过房间号直接进入。\n'
                '支持单独的 ttwid 值、完整 Cookie 请求头，以及插件导出的 Netscape cookies.txt。'
                '请使用 douyin.com 的文件；斗鱼 douyu.com 的 Cookie 不能用于抖音。\n'
                '留空并保存可恢复默认；导入成功不代表获得额外访问权限。',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _input,
                minLines: 2,
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  hintText: '粘贴 ttwid、Cookie 请求头或 Netscape 文件内容',
                  border: OutlineInputBorder(),
                  errorMaxLines: 2,
                ),
                validator: (value) =>
                    DouyinAccountService.validateCookie(value ?? ''),
              ),
              CookieFileImportButton(
                controller: _input,
                validate: DouyinAccountService.validateCookie,
                normalize: DouyinAccountService.normalizeCookie,
              ),
              TextButton.icon(
                onPressed: _input.clear,
                icon: const Icon(Icons.restore),
                label: const Text('恢复默认 ttwid'),
              ),
              const Text(
                'Cookie 包含登录凭据，请勿分享 Cookie、备份文件或配置截图。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('取消')),
        TextButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
