import 'package:path/path.dart' as p;

import '../models/clean_models.dart';

/// Independently maintained rules. Targets are explicit disposable leaves,
/// never installation roots, personal documents or a vendor's entire profile.
enum CleanupRoot { local, roaming, windows }

class FileCleanupRule {
  const FileCleanupRule({
    required this.id,
    required this.name,
    required this.category,
    required this.root,
    required this.locations,
    required this.note,
    this.extensions = const {},
    this.filenames = const {},
    this.minAge,
    this.namePattern,
    this.recursive = true,
  });
  final String id, name, note;
  final CleanCategory category;
  final CleanupRoot root;
  final List<String> locations;
  final Set<String> extensions, filenames;
  final Duration? minAge;
  final String? namePattern;
  final bool recursive;

  bool accepts(String name) {
    final normalized = name.toLowerCase();
    return (extensions.isEmpty ||
            extensions.contains(p.extension(normalized))) &&
        (filenames.isEmpty || filenames.contains(normalized)) &&
        (namePattern == null ||
            RegExp(namePattern!, caseSensitive: false).hasMatch(name));
  }
}

const _cacheNote = '仅此软件的可重建缓存；清理后首次打开可能需要重新加载。';

final softwareCacheRules = <FileCleanupRule>[
  FileCleanupRule(
    id: 'qqlive_web',
    name: '腾讯视频网页缓存',
    category: CleanCategory.appCache,
    root: CleanupRoot.roaming,
    locations: ['Tencent/QQLive/webkit_cache'],
    note: _cacheNote,
  ),
  // Local inspection confirmed these Electron/Chromium disposable leaves.
  for (final application in [
    ('workbuddy', 'WorkBuddy', 'WorkBuddy'),
    ('trae', 'Trae', 'Trae'),
    ('trae_cn', 'Trae CN', 'Trae CN'),
    ('youku_app', '优酷视频', 'youku-app'),
    ('bilibili', '哔哩哔哩', 'bilibili'),
  ])
    FileCleanupRule(
      id: application.$1,
      name: application.$2,
      category: CleanCategory.appCache,
      root: CleanupRoot.roaming,
      locations: [
        '${application.$3}/Cache',
        '${application.$3}/Code Cache',
        '${application.$3}/CachedData',
      ],
      note: _cacheNote,
    ),
  FileCleanupRule(
    id: 'widgets_web_cache',
    name: 'Windows 小组件网页缓存',
    category: CleanCategory.appCache,
    root: CleanupRoot.local,
    locations: [
      'Packages/MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy/LocalState/EBWebView/Default/Cache',
    ],
    namePattern: r'^(?:f_.*|data_.*|index)$',
    note: '仅小组件网页缓存索引与资源；不清理账户、会话或离线数据。',
  ),
  FileCleanupRule(
    id: 'widgets_code_cache',
    name: 'Windows 小组件脚本缓存',
    category: CleanCategory.appCache,
    root: CleanupRoot.local,
    locations: [
      'Packages/MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy/LocalState/EBWebView/Default/Code Cache',
    ],
    namePattern: r'^.*_0$',
    note: '仅小组件脚本编译缓存；不含 GPU、存储、会话和账户信息。',
  ),
  FileCleanupRule(
    id: 'code',
    name: 'Visual Studio Code',
    category: CleanCategory.appCache,
    root: CleanupRoot.roaming,
    locations: ['Code/Cache', 'Code/Code Cache', 'Code/CachedData'],
    note: _cacheNote,
  ),
  FileCleanupRule(
    id: 'code_insiders',
    name: 'VS Code Insiders',
    category: CleanCategory.appCache,
    root: CleanupRoot.roaming,
    locations: [
      'Code - Insiders/Cache',
      'Code - Insiders/Code Cache',
      'Code - Insiders/CachedData',
    ],
    note: _cacheNote,
  ),
  FileCleanupRule(
    id: 'cursor',
    name: 'Cursor',
    category: CleanCategory.appCache,
    root: CleanupRoot.roaming,
    locations: ['Cursor/Cache', 'Cursor/Code Cache', 'Cursor/CachedData'],
    note: _cacheNote,
  ),
  FileCleanupRule(
    id: 'windsurf',
    name: 'Windsurf',
    category: CleanCategory.appCache,
    root: CleanupRoot.roaming,
    locations: ['Windsurf/Cache', 'Windsurf/Code Cache', 'Windsurf/CachedData'],
    note: _cacheNote,
  ),
  FileCleanupRule(
    id: 'discord',
    name: 'Discord',
    category: CleanCategory.appCache,
    root: CleanupRoot.roaming,
    locations: ['discord/Cache', 'discord/Code Cache'],
    note: _cacheNote,
  ),
  FileCleanupRule(
    id: 'slack',
    name: 'Slack',
    category: CleanCategory.appCache,
    root: CleanupRoot.roaming,
    locations: ['Slack/Cache', 'Slack/Code Cache'],
    note: _cacheNote,
  ),
  FileCleanupRule(
    id: 'spotify',
    name: 'Spotify',
    category: CleanCategory.appCache,
    root: CleanupRoot.local,
    locations: ['Spotify/Browser/Cache', 'Spotify/Cache'],
    note: _cacheNote,
  ),
  FileCleanupRule(
    id: 'teams',
    name: 'Microsoft Teams',
    category: CleanCategory.appCache,
    root: CleanupRoot.roaming,
    locations: ['Microsoft/Teams/Cache', 'Microsoft/Teams/Code Cache'],
    note: _cacheNote,
  ),
  FileCleanupRule(
    id: 'dingtalk',
    name: '钉钉',
    category: CleanCategory.appCache,
    root: CleanupRoot.local,
    locations: ['DingDing/Cache'],
    note: _cacheNote,
  ),
  FileCleanupRule(
    id: 'wps_http',
    name: 'WPS 网页资源缓存',
    category: CleanCategory.appCache,
    root: CleanupRoot.local,
    locations: [
      'kingsoft/wps/cache/http',
      'kingsoft/et/cache/http',
      'kingsoft/wpp/cache/http',
    ],
    note: _cacheNote,
  ),
  FileCleanupRule(
    id: 'wps_web',
    name: 'WPS 首页缓存',
    category: CleanCategory.appCache,
    root: CleanupRoot.roaming,
    locations: [
      'kingsoft/office6/homepage/cache',
      'kingsoft/office6/homepage/cef/cache',
    ],
    note: _cacheNote,
  ),
  // Compatibility with existing installs that keep these leaves in Local.
  FileCleanupRule(
    id: 'electron_local',
    name: '桌面软件缓存',
    category: CleanCategory.appCache,
    root: CleanupRoot.local,
    locations: [
      'Code/Cache',
      'Discord/Cache',
      'Slack/Cache',
      'Microsoft/Teams/Cache',
    ],
    note: _cacheNote,
  ),
];

const additionalSystemRules = <FileCleanupRule>[
  FileCleanupRule(
    id: 'thumb_pending',
    name: '待删除的缩略图缓存',
    category: CleanCategory.systemCache,
    root: CleanupRoot.local,
    locations: ['Microsoft/Windows/Explorer/ThumbCacheToDelete'],
    namePattern: r'^thm.*\.tmp$',
    recursive: false,
    note: '仅系统待删除目录的 thm*.tmp；不删除图片。',
  ),
  FileCleanupRule(
    id: 'icon_pending',
    name: '待删除的图标缓存',
    category: CleanCategory.systemCache,
    root: CleanupRoot.local,
    locations: ['Microsoft/Windows/Explorer/IconCacheToDelete'],
    namePattern: r'^icn.*\.tmp$',
    recursive: false,
    note: '仅系统待删除目录的 icn*.tmp；不处理图标资源和其他文件。',
  ),
  FileCleanupRule(
    id: 'rdp_bitmap',
    name: '远程桌面位图缓存',
    category: CleanCategory.systemCache,
    root: CleanupRoot.local,
    locations: ['Microsoft/Terminal Server Client/Cache'],
    extensions: {'.bmc'},
    recursive: false,
    note: '仅可重建的 .bmc 位图缓存；不删除连接配置，首次连接可能重新传输图像。',
  ),
  FileCleanupRule(
    id: 'legacy_webcache_old',
    name: '旧版网页缓存备份',
    category: CleanCategory.systemCache,
    root: CleanupRoot.local,
    locations: ['Microsoft/Windows/WebCache.old'],
    minAge: Duration(days: 7),
    note: '仅 WebCache.old 中七天前的文件；不处理正在使用的 WebCache 数据库。',
  ),
  FileCleanupRule(
    id: 'legacy_icon',
    name: '系统图标缓存（用户）',
    category: CleanCategory.systemCache,
    root: CleanupRoot.local,
    locations: [''],
    filenames: {'iconcache.db'},
    recursive: false,
    note: '清理后图标需要重新生成，当前占用的文件会跳过。',
  ),
  FileCleanupRule(
    id: 'user_font_files',
    name: '用户字体缓存文件',
    category: CleanCategory.systemCache,
    root: CleanupRoot.local,
    locations: [''],
    filenames: {'fntcache.dat', 'gdipfontcachev1.dat'},
    recursive: false,
    note: '不含字体文件，清理后字体缓存需要重新生成。',
  ),
  FileCleanupRule(
    id: 'roaming_cryptnet',
    name: '证书下载缓存（Roaming）',
    category: CleanCategory.systemCache,
    root: CleanupRoot.roaming,
    locations: [
      'Microsoft/CryptnetUrlCache/Content',
      'Microsoft/CryptnetUrlCache/MetaData',
    ],
    note: '只清理证书下载缓存，不删除已安装证书和密钥。',
  ),
];

const additionalLogRules = <FileCleanupRule>[
  FileCleanupRule(
    id: 'clr_user_logs',
    name: '.NET 用户运行日志',
    category: CleanCategory.systemLogs,
    root: CleanupRoot.local,
    locations: ['Microsoft/clr_v4.0', 'Microsoft/clr_v4.0_32'],
    extensions: {'.log'},
    minAge: Duration(days: 7),
    recursive: false,
    note: '仅七天前的 .log；不删除运行时、程序集、配置或 NativeImages。',
  ),
  FileCleanupRule(
    id: 'tencent_logs',
    name: '腾讯产品日志',
    category: CleanCategory.systemLogs,
    root: CleanupRoot.roaming,
    locations: ['Tencent/Logs'],
    extensions: {'.log', '.old', '.etl'},
    minAge: Duration(days: 7),
    note: '仅七天前的诊断日志，不含聊天记录、附件和下载文件。',
  ),
  FileCleanupRule(
    id: 'tencent_local_logs',
    name: '腾讯产品日志（本地）',
    category: CleanCategory.systemLogs,
    root: CleanupRoot.local,
    locations: ['Tencent/Logs'],
    extensions: {'.log', '.old', '.etl'},
    minAge: Duration(days: 7),
    note: '仅七天前的诊断日志，不含聊天记录和附件。',
  ),
  FileCleanupRule(
    id: 'dotnet_logs',
    name: '.NET Framework 日志',
    category: CleanCategory.systemLogs,
    root: CleanupRoot.windows,
    locations: ['Microsoft.NET/Framework', 'Microsoft.NET/Framework64'],
    extensions: {'.log'},
    minAge: Duration(days: 7),
    note: '仅七天前的 .log；不清理程序集、NativeImages、配置和运行时组件。',
  ),
];

/// One list shared by browser-cache and configured-download discovery.
List<(String, String)> browserProfileRoots(String local, String roaming) => [
  for (final (name, relative) in const [
    ('Chrome', 'Google/Chrome/User Data'),
    ('Chrome Beta', 'Google/Chrome Beta/User Data'),
    ('Chrome Dev', 'Google/Chrome Dev/User Data'),
    ('Chrome Canary', 'Google/Chrome SxS/User Data'),
    ('Edge', 'Microsoft/Edge/User Data'),
    ('Edge Beta', 'Microsoft/Edge Beta/User Data'),
    ('Edge Dev', 'Microsoft/Edge Dev/User Data'),
    ('Edge Canary', 'Microsoft/Edge SxS/User Data'),
    ('Firefox', 'Mozilla/Firefox/Profiles'),
    ('Brave', 'BraveSoftware/Brave-Browser/User Data'),
    ('Chromium', 'Chromium/User Data'),
    ('Vivaldi', 'Vivaldi/User Data'),
    ('Opera', 'Opera Software'),
    ('QQ浏览器', 'Tencent/QQBrowser/User Data'),
    ('QQ浏览器', 'Tencent/QQBrowser'),
    ('360极速浏览器', '360Chrome/Chrome/User Data'),
    ('360极速浏览器X', '360ChromeX/Chrome/User Data'),
    ('搜狗浏览器', 'Sogou/SogouExplorer/User Data'),
    ('Yandex', 'Yandex/YandexBrowser/User Data'),
    ('百分浏览器', 'CentBrowser/User Data'),
  ])
    (name, p.joinAll([local, ...relative.split('/')])),
  for (final (name, relative) in const [
    ('Opera', 'Opera Software'),
    ('QQ浏览器', 'Tencent/QQBrowser'),
    ('360安全浏览器', '360se6/User Data'),
    ('360安全浏览器', 'secoresdk/360se6/User Data'),
    ('搜狗浏览器', 'SogouExplorer'),
  ])
    (name, p.joinAll([roaming, ...relative.split('/')])),
];

/// Known profile containers; only explicit resource-cache leaves are discovered.
List<(String, String)> softwareCacheProfiles(String local, String roaming) => [
  for (final (name, relative) in const [
    ('WorkBuddy', 'WorkBuddy/Partitions'),
    ('腾讯视频', 'Tencent/QQLive/Cef43'),
    ('腾讯视频', 'Tencent/QQLive/Webkit3'),
    ('腾讯视频', 'Tencent/QQLive/WebView2'),
  ])
    (name, p.joinAll([roaming, ...relative.split('/')])),
];
