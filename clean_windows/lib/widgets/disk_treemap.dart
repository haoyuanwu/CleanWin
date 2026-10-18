import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/path_utils.dart';
import '../services/disk_services.dart';

class DiskMapRect {
  const DiskMapRect(this.node, this.rect);
  final DirUsage node;
  final Rect rect;
}

/// Binary partition preserves actual byte-to-area ratios, without log scaling.
List<DiskMapRect> layoutDiskMap(List<DirUsage> nodes, Size size) {
  final output = <DiskMapRect>[];
  void partition(List<DirUsage> items, Rect bounds) {
    if (items.isEmpty) return;
    if (items.length == 1) {
      output.add(DiskMapRect(items.single, bounds));
      return;
    }
    final total = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    var sum = 0;
    var split = 1;
    var best = double.infinity;
    for (var i = 0; i < items.length - 1; i++) {
      sum += items[i].sizeBytes;
      final difference = (total / 2 - sum).abs();
      if (difference < best) {
        best = difference;
        split = i + 1;
      }
    }
    final first = items.take(split).toList();
    final ratio =
        first.fold<int>(0, (sum, item) => sum + item.sizeBytes) / total;
    if (bounds.width >= bounds.height) {
      final cut = bounds.width * ratio;
      partition(
        first,
        Rect.fromLTWH(bounds.left, bounds.top, cut, bounds.height),
      );
      partition(
        items.skip(split).toList(),
        Rect.fromLTWH(
          bounds.left + cut,
          bounds.top,
          bounds.width - cut,
          bounds.height,
        ),
      );
    } else {
      final cut = bounds.height * ratio;
      partition(
        first,
        Rect.fromLTWH(bounds.left, bounds.top, bounds.width, cut),
      );
      partition(
        items.skip(split).toList(),
        Rect.fromLTWH(
          bounds.left,
          bounds.top + cut,
          bounds.width,
          bounds.height - cut,
        ),
      );
    }
  }

  final sorted = nodes.where((item) => item.sizeBytes > 0).toList()
    ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  partition(sorted, Offset.zero & size);
  return output;
}

class DiskTreemap extends StatelessWidget {
  const DiskTreemap({super.key, required this.usage, required this.onTap});
  final DirUsage usage;
  final void Function(DirUsage node) onTap;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final nodes = layoutDiskMap(
        usage.children,
        Size(
          constraints.maxWidth,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 400,
        ),
      );
      if (nodes.isEmpty) return const Center(child: Text('无可显示的子项'));
      return Stack(
        children: [
          for (var i = 0; i < nodes.length; i++)
            if (nodes[i].rect.width > 1 && nodes[i].rect.height > 1)
              _Tile(
                node: nodes[i].node,
                rect: nodes[i].rect.deflate(
                  math.min(
                    2,
                    math.min(nodes[i].rect.width, nodes[i].rect.height) / 4,
                  ),
                ),
                onTap: onTap,
                index: i,
              ),
        ],
      );
    },
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.node,
    required this.rect,
    required this.onTap,
    required this.index,
  });

  final DirUsage node;
  final Rect rect;
  final void Function(DirUsage node) onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(index);
    // 最小块也能显示名称
    final showSize = rect.height >= 72 && rect.width >= 120;

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Tooltip(
        message:
            '${node.name}\n${formatBytes(node.sizeBytes)}\n${node.fileCount} 文件\n${node.path}',
        waitDuration: const Duration(milliseconds: 250),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: node.isDirectory ? () => onTap(node) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: rect.width < 60 || rect.height < 40
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          maxLines: rect.height >= 64 ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        if (showSize) ...[
                          const Spacer(),
                          Text(
                            formatBytes(node.sizeBytes),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Color _colorFor(int index) {
    // 由大到小：深蓝 → 青 → 紫，便于视觉排序
    final hue = 210.0 - (index * 2.2).clamp(0, 70);
    final light = 0.34 + (index * 0.012).clamp(0, 0.16);
    return HSLColor.fromAHSL(1, hue, 0.52, light).toColor();
  }
}
