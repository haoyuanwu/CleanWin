# 注册表清理扫描

## 当前范围（2026-10-17）

仅扫描具有逐值清理规则的类别，结果按类别分组且默认折叠。分类复选框可以选择整类，
展开后可以单独勾选；搜索不改变已有选择。开始新扫描时清空选择并重新折叠分类。

| 类别 | 扫描根 | 可清理条件 |
| --- | --- | --- |
| 启动命令 | Software/Microsoft/Windows/CurrentVersion/Run、RunOnce | 命名字符串值指向明确缺失的绝对程序或脚本目标 |
| 程序路径 | Software/Microsoft/Windows/CurrentVersion/App Paths | 仅直接子键的默认字符串值，目标 exe 明确缺失 |
| MUI 缓存 | Software/Classes/Local Settings/Software/Microsoft/Windows/Shell/MuiCache；Software/Microsoft/Windows/ShellNoRoam/MUICache | 值名与缺失 exe 精确匹配 |

启动命令和程序路径分别检查 HKCU/HKLM、32/64 位原生视图；MUI 只查 HKCU。
32 位系统仅检查 32 位视图。64 位系统共 16 个逻辑扫描位置，实际存在的根因系统而异。
不再扫描卸载信息、策略启动、COM、类型库、文件关联、打开命令、右键菜单、共享 DLL、字体等只读类别。

## 判定与缓存

- 非字符串、无法解析的相对路径、UNC 或不支持的目标类型不进入可清理结果。
- 目标不存在才报告；盘符离线、拒绝访问和其他未知状态不视为缺失。
- 32 位视图的 System32 目标额外核对 SysWOW64，避免误报。
- 服务和应用状态均过滤不可清理记录，页面不再需要“只看可清理项”筛选。
- 缓存使用 registry_cleanable_v4，与旧版只读审计缓存隔离。失败不覆盖上次有效缓存。
- 扫描范围详情仍提供位置、视图、检查次数和未读取位置。

## 清理约束

后端复核 hive、视图、白名单根、准确值名、数据类型、原值及目标。默认值用空字符串，
无值名用 null，两者不会混淆。原值或目标变化、目标恢复、无法确认缺失时拒绝处理。
先将单值快照写入 %LOCALAPPDATA%/CleanWin/registry_backups/<GUID>.json，
备份成功后才调用 DeleteValue，不删除整键。备份目前没有一键恢复界面。

## 验证

测试覆盖只读类别剔除、旧缓存隔离、扫描脚本范围与语法、目标状态区分、精确视图身份、
默认值与 null、备份先于删除、分类默认折叠、跨类别勾选隔离、搜索保留选择与刷新锁定。
验证不实际删除用户注册表数据。
