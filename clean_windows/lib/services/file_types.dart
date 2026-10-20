String fileKind(String name) {
  final extension = name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
  return switch (extension) {
    'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'iso' => '压缩 / 镜像',
    'mp4' || 'mkv' || 'avi' || 'mov' || 'mp3' || 'wav' || 'flac' => '影音',
    'exe' || 'msi' || 'msix' || 'apk' => '安装包',
    _ => '其他',
  };
}

const fileKinds = ['压缩 / 镜像', '影音', '安装包', '其他'];
