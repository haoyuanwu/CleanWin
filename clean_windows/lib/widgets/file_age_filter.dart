import 'package:flutter/material.dart';

import 'page_shell.dart';

enum FileAge {
  all('全部时间'),
  recent('近 30 天修改'),
  old('超过 30 天未修改'),
  older('超过 180 天未修改');

  const FileAge(this.label);
  final String label;

  bool includes(DateTime? modified) {
    if (this == all) return true;
    if (modified == null) return false;
    final days = DateTime.now().difference(modified).inDays;
    return switch (this) {
      all => true,
      recent => days >= 0 && days < 30,
      old => days >= 30,
      older => days >= 180,
    };
  }
}

class FileAgeFilter extends StatelessWidget {
  const FileAgeFilter({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final FileAge value;
  final ValueChanged<FileAge> onChanged;

  @override
  Widget build(BuildContext context) => ModuleSelect<FileAge>(
    label: '按最后修改时间筛选',
    value: value,
    items: [
      for (final age in FileAge.values)
        ModuleSelectItem(value: age, child: Text(age.label)),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}
