import 'package:path/path.dart' as p;

import 'file_types.dart';

/// Small immutable inputs: never copy scan snapshots/signatures to the worker.
typedef DownloadListEntry = ({
  int index,
  String id,
  String name,
  String path,
  String root,
  int bytes,
  DateTime? modified,
});

class DownloadListRequest {
  const DownloadListRequest(
    this.entries, {
    this.query = '',
    this.kind,
    this.minimumDays,
    this.maximumDays,
  });
  final List<DownloadListEntry> entries;
  final String query;
  final String? kind;
  final int? minimumDays;
  final int? maximumDays;
}

class DownloadFolderGroup {
  DownloadFolderGroup(this.path);
  final String path;
  final List<int> indices = [];
  int bytes = 0;
}

class DownloadListIndex {
  final groups = <DownloadFolderGroup>[];
  final kindBytes = <String, int>{};
  final kindCounts = <String, int>{};
  final sizeById = <String, int>{};
  int totalBytes = 0;
  int visibleCount = 0;
}

String downloadFolder(String path, String id) {
  final paths = p.windows.isAbsolute(path) ? p.windows : p.posix;
  // Software managers expose one reviewed package snapshot per download root.
  return paths.normalize(
    id.startsWith('dl_software_') ? path : paths.dirname(path),
  );
}

DownloadListIndex buildDownloadListIndex(DownloadListRequest request) {
  final result = DownloadListIndex();
  final groups = <String, DownloadFolderGroup>{};
  final entries = request.entries;
  final now = DateTime.now();
  final query = request.query.trim().toLowerCase();
  for (final item in entries) {
    final kind = fileKind(item.name);
    result.totalBytes += item.bytes;
    result.sizeById[item.id] = item.bytes;
    result.kindBytes.update(
      kind,
      (value) => value + item.bytes,
      ifAbsent: () => item.bytes,
    );
    result.kindCounts.update(kind, (value) => value + 1, ifAbsent: () => 1);
    if (request.kind != null && kind != request.kind) continue;
    if (query.isNotEmpty &&
        !'${item.name} ${item.path}'.toLowerCase().contains(query)) {
      continue;
    }
    if (request.minimumDays != null || request.maximumDays != null) {
      if (item.modified == null) continue;
      final days = now.difference(item.modified!).inDays;
      if (request.minimumDays != null && days < request.minimumDays!) continue;
      if (request.maximumDays != null && days >= request.maximumDays!) continue;
    }
    final key = p.windows.isAbsolute(item.root)
        ? item.root.toLowerCase()
        : item.root;
    final group = groups.putIfAbsent(key, () => DownloadFolderGroup(item.root));
    group.indices.add(item.index);
    group.bytes += item.bytes;
    result.visibleCount++;
  }
  final bytesByIndex = {for (final item in entries) item.index: item.bytes};
  for (final group in groups.values) {
    group.indices.sort((a, b) {
      final order = bytesByIndex[b]!.compareTo(bytesByIndex[a]!);
      return order == 0 ? a.compareTo(b) : order;
    });
  }
  result.groups.addAll(groups.values);
  result.groups.sort((a, b) {
    final order = b.bytes.compareTo(a.bytes);
    return order == 0 ? a.path.compareTo(b.path) : order;
  });
  return result;
}
