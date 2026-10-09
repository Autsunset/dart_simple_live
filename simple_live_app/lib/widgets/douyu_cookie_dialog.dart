import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/widgets/cookie_file_import_button.dart';

class DouyuCookieDialog extends StatefulWidget {
  final String initialValue;

  const DouyuCookieDialog({super.key, required this.initialValue});

  static Future<bool> configure() async {
    final account = DouyuAccountService.instance;
    final value = await Get.dialog<String>(
      DouyuCookieDialog(initialValue: account.cookie),
    );
    if (value == null) return false;
    try {
      await account.setCookie(value);
      SmartDialog.showToast(
        value.isEmpty ? '已恢复斗鱼匿名模式' : '斗鱼 Cookie 已保存，实际画质以平台返回为准',
      );
      return true;
    } catch (_) {
      SmartDialog.showToast('保存失败，原有斗鱼配置未更改');
      return false;
    }
  }

  @override
  State<DouyuCookieDialog> createState() => _DouyuCookieDialogState();
}

class _DouyuCookieDialogState extends State<DouyuCookieDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _input = TextEditingController(text: widget.initialValue);

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Get.back(result: DouyuAccountService.normalizeCookie(_input.text));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('斗鱼 Cookie（可选）'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '普通观看可继续匿名使用；原画等高码率档位可能要求登录状态。\n'
                '支持直接粘贴插件导出的 Netscape 文件内容、导入 cookies.txt，'
                '或粘贴请求头的 name=value 格式。请导出 douyu.com 的 Cookie，包含 acf_did；'
                '抖音 douyin.com 的 Cookie 不能用于斗鱼。\n'
                '保存后仍由平台决定可用画质，不保证解除所有限制。',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _input,
                minLines: 2,
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  hintText: '粘贴 Netscape 文件内容或 acf_did=...; acf_auth=...',
                  border: OutlineInputBorder(),
                  errorMaxLines: 2,
                ),
                validator: (value) =>
                    DouyuAccountService.validateCookie(value ?? ''),
              ),
              CookieFileImportButton(
                controller: _input,
                validate: DouyuAccountService.validateCookie,
                normalize: DouyuAccountService.normalizeCookie,
              ),
              TextButton.icon(
                onPressed: _input.clear,
                icon: const Icon(Icons.restore),
                label: const Text('清除 Cookie，恢复匿名'),
              ),
              const Text(
                'Cookie 是登录凭据，设置备份也可能包含它。请勿分享 Cookie、备份文件或截图。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('取消')),
        TextButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
