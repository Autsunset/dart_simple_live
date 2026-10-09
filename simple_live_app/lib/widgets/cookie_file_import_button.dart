import 'package:flutter/material.dart';
import 'package:simple_live_app/app/utils/cookie_file.dart';

class CookieFileImportButton extends StatefulWidget {
  final TextEditingController controller;
  final String? Function(String) validate;
  final String Function(String) normalize;

  const CookieFileImportButton({
    super.key,
    required this.controller,
    required this.validate,
    required this.normalize,
  });

  @override
  State<CookieFileImportButton> createState() => _CookieFileImportButtonState();
}

class _CookieFileImportButtonState extends State<CookieFileImportButton> {
  bool _loading = false;
  String? _message;
  bool _failed = false;

  Future<void> _import() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final text = await CookieFile.pickText();
      if (!mounted || text == null) return;
      final error = widget.validate(text);
      if (error != null) {
        setState(() {
          _failed = true;
          _message = error;
        });
        return;
      }
      widget.controller.text = widget.normalize(text);
      setState(() {
        _failed = false;
        _message = '文件已载入，点击保存后生效';
      });
    } on CookieFileException catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = '读取 Cookie 文件失败，原输入未更改';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _loading ? null : _import,
          icon: const Icon(Icons.file_open_outlined),
          label: Text(_loading ? '正在读取…' : '导入 cookies.txt'),
        ),
        if (_message != null)
          Text(
            _message!,
            style: TextStyle(
              fontSize: 12,
              color: _failed ? Theme.of(context).colorScheme.error : null,
            ),
          ),
      ],
    );
  }
}
