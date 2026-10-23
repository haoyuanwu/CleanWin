import 'dart:io';
import 'dart:collection';

import 'package:path/path.dart' as p;

/// Explicit disposable directory names; never match arbitrary substrings such
/// as MyCacheBackup, UserData, Service Worker or installer package caches.
const disposableCacheNames = {
  'cache',
  'caches',
  'cache2',
  'code cache',
  'code_cache',
  'gpucache',
  'shadercache',
  'shader_cache',
  'grshadercache',
  'dawncache',
  'dawngraphitecache',
  'dawnwebgpucache',
  'cacheddata',
  'cached data',
  'cachestorage',
  'cache_storage',
  'scriptcache',
  'startupcache',
  'imagecache',
  'image_cache',
  'webcache',
  'web_cache',
  'httpcache',
  'http_cache',
  'media cache',
  'media cache files',
  'crashpad',
};

/// Shallow daily discovery excludes shader, offline/service-worker and media stores.
const quickSoftwareCacheNames = {
  'cache',
  'caches',
  'code cache',
  'code_cache',
  'cacheddata',
  'cached data',
  'httpcache',
  'http_cache',
  'imagecache',
  'image_cache',
  'webcache',
  'web_cache',
};

/// Walk one directory at a time so an inaccessible child does not abort siblings.
/// Prune at the depth limit rather than recursively enumerating the whole tree.
Stream<FileSystemEntity> walkFiles(
  Directory root, {
  bool recursive = true,
  bool Function(String path)? exclude,
  void Function(FileSystemException error)? onError,
  void Function(String path)? onPath,
  bool Function()? cancelled,
}) async* {
  if (exclude?.call(root.path) ?? false) return;
  final pending = <Directory>[root];
  while (pending.isNotEmpty) {
    if (cancelled?.call() ?? false) return;
    final dir = pending.removeLast();
    if (FileSystemEntity.typeSync(dir.path, followLinks: false) ==
        FileSystemEntityType.link) {
      continue;
    }
    onPath?.call(dir.path);
    try {
      await for (final child in dir.list(followLinks: false)) {
        if (cancelled?.call() ?? false) return;
        if (exclude?.call(child.path) ?? false) continue;
        if (child is Directory && recursive) {
          pending.add(child);
        } else if (child is File) {
          onPath?.call(child.path);
          yield child;
        }
      }
    } on FileSystemException catch (error) {
      onError?.call(error);
      // Keep scanning other directories after a denied or vanished directory.
    }
  }
}

Stream<Directory> discoverCaches(
  Directory root, {
  int maxDepth = 8,
  int profileDepth = 0,
  bool breadthFirst = false,
  int? maxDirectories,
  void Function(String path)? onLimit,
  Set<String> cacheNames = disposableCacheNames,
  bool includePackageTemp = true,
  bool pruneCaches = false,
  bool Function(String path)? exclude,
  void Function(FileSystemException error)? onError,
  void Function(String path)? onPath,
  bool Function()? cancelled,
}) async* {
  final pending = Queue<(Directory, int)>.of([(root, 0)]);
  var visited = 0;
  while (pending.isNotEmpty) {
    if (cancelled?.call() ?? false) return;
    final (dir, depth) = breadthFirst
        ? pending.removeFirst()
        : pending.removeLast();
    if (protectedCachePath(dir.path)) continue;
    if (FileSystemEntity.typeSync(dir.path, followLinks: false) ==
        FileSystemEntityType.link) {
      continue;
    }
    if (exclude?.call(dir.path) ?? false) continue;
    if (maxDirectories != null && visited >= maxDirectories) {
      onLimit?.call(root.path);
      return;
    }
    visited++;
    onPath?.call(dir.path);
    if (depth > 0) {
      final name = p.basename(dir.path).toLowerCase();
      final packageTemp =
          name == 'tempstate' &&
          p.basename(p.dirname(p.dirname(dir.path))).toLowerCase() ==
              'packages';
      if (cacheNames.contains(name) || (includePackageTemp && packageTemp)) {
        yield dir;
        continue; // A cache root owns its children; do not count them twice.
      }
      if (pruneCaches && disposableCacheNames.contains(name)) continue;
      if ({
        'node_modules',
        'downloads',
        'download',
        'quarantine',
        'nplayerdisk',
        'xcdn',
        'local_files',
        'cachefile',
        '.git',
        'winsxs',
        'installer',
        'package cache',
        'installer cache',
        'cached installers',
        'installshield',
        'windowsapps',
        'temp',
        'cookies',
        'local storage',
        'indexeddb',
        'session storage',
        'file storage',
        'filestorage',
        'msgattach',
      }.contains(name)) {
        continue;
      }
    }
    if (depth >= maxDepth) {
      // Only known profile containers receive extra depth; arbitrary application
      // trees stay bounded, including on machines with other installed software.
      final segments = p
          .split(p.relative(dir.path, from: root.path))
          .map((s) => s.toLowerCase());
      final inProfile = segments.any(
        (s) => const {
          'user data',
          'userdata',
          'profiles',
          'partitions',
          'localcache',
          'localstate',
          'ebwebview',
          'webview2',
        }.contains(s),
      );
      if (profileDepth <= 0 || !inProfile || depth >= maxDepth + profileDepth) {
        continue;
      }
    }
    try {
      await for (final child in dir.list(followLinks: false)) {
        if (child is Directory) pending.add((child, depth + 1));
      }
    } on FileSystemException catch (error) {
      onError?.call(error);
      // A denied application must not hide caches belonging to other apps.
    }
  }
}

/// Offline dependencies and application state need explicit management.
bool protectedCachePath(String path) {
  const protected = {
    'pub',
    '.pub-cache',
    '.nuget',
    '.gradle',
    '.m2',
    '.npm',
    'npm-cache',
    'pip',
    'uv',
    'huggingface',
    'torch',
    'ollama',
    'models',
    'offline',
    'offlinecache',
    'offline cache',
    'cleanwin',
  };
  return p.windows
      .normalize(path)
      .toLowerCase()
      .split('\\')
      .any(protected.contains);
}

/// Generic software-cache discovery must not walk Windows service data stores.
/// Explicit system cleanup rules still own their narrow, supported targets.
bool systemServiceDataPath(String path, String programData) {
  final context = p.windows;
  final root = context.normalize(programData).toLowerCase();
  final target = context.normalize(path).toLowerCase();
  if (!context.isWithin(root, target)) return false;
  final relative = context.relative(target, from: root);
  const serviceRoots = {
    'packages',
    'windowsholographicdevices',
    'usoprivate',
    'usoshared',
    r'windows master store\servicedata',
    r'microsoft\diagnosis',
    r'microsoft\smsrouter',
    r'microsoft\windows',
    r'microsoft\windows defender',
    r'microsoft\crypto',
    r'microsoft\vault',
  };
  return serviceRoots.any(
    (service) => relative == service || relative.startsWith('$service\\'),
  );
}
