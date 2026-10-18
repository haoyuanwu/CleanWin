import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/file_safety.dart';

Future<String?> pickScanDirectory(
  BuildContext context, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  String? error;
  bool checking = false;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(
        title: const Text('指定扫描目录'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '完整文件夹路径',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 8),
              const Text('只分析此目录；不会自动勾选或删除文件。', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: checking ? null : () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: checking
                ? null
                : () async {
                    update(() {
                      checking = true;
                      error = null;
                    });
                    final path = controller.text.trim();
                    bool valid = false;
                    try {
                      valid =
                          p.isAbsolute(path) &&
                          await Directory(path)
                              .exists()
                              .timeout(const Duration(seconds: 5)) &&
                          !await hasLinkedAncestorAsync(path);
                    } catch (_) {}
                    if (!ctx.mounted) return;
                    if (valid) {
                      Navigator.pop(ctx, p.normalize(path));
                    } else {
                      update(() {
                        checking = false;
                        error = '目录不存在、无法访问或包含链接，请检查完整路径';
                      });
                    }
                  },
            child: Text(checking ? '检查中…' : '使用此目录'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}
