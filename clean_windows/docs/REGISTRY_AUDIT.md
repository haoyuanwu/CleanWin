# 注册表维护（2026-10-23）

系统维护只呈现能逐值核对、备份和恢复的失效记录。结果分类默认折叠，手动勾选；搜索与类别筛选不改变选择，重扫不先清空已显示数据。空泛的建议和只读问题计数已移除。

| 类别 | 范围与条件 |
| --- | --- |
| 启动命令 | HKCU/HKLM Run、RunOnce 的命名字符串值，绝对程序/脚本明确缺失 |
| 程序路径 | App Paths 直接子键的默认字符串值，仅缺失 exe |
| MUI 缓存 | 当前用户两个 MUICache 根，值名与缺失 exe 精确一致 |
| 字体记录 | Windows NT/CurrentVersion/Fonts，缺失 ttf/otf/ttc/fon；相对文件名同时核对 Windows 和用户 Fonts，未知或存在则跳过 |
| 共享库引用 | 仅 HKLM SharedDLLs、DWord 引用数为 0、值名对应缺失 dll/ocx；正引用计数不处理 |
| 打开方式 | Classes/Applications/*.exe/shell/open/command 默认字符串值，目标明确缺失，无 DelegateExecute |
| 右键命令 | Classes 下 *、AllFilesystemObjects、Directory、Directory/Background、Drive、Folder 的 shell/直接动词/command 默认值，无委托执行，目标明确缺失 |

32/64 位视图分开，当前用户与机器范围分开；64 位 Windows 为 50 个逻辑根，位置可不存在。共享视图仍保持精确身份。COM/ActiveX、TypeLib、文件关联 ProgID、卸载 MSI 登记、服务、策略和防火墙不纳入清理；不会只因链接目标暂不可用就删除整键。

扫描阶段只打开可写句柄验证权限，不写值。离线盘符、拒绝访问、不支持的类型、相对命令、无法确定的目标均不列为可清理。32 位 System32 目标另核对 SysWOW64。字体相对文件名先检查另一 Fonts 目录，两个目标不确定时跳过。

删除前再次核对准确 hive/view/root、值名、类型、原值、解析目标、目标仍缺失以及 DelegateExecute。仅 DeleteValue；先写 `%LOCALAPPDATA%/CleanWin/registry_backups/<GUID>.json`，备份失败不删除。恢复同样限制根和类型，按原始 String/ExpandString/DWord 恢复，不覆盖已存在值。备份恢复独立位于注册表页面，“任务与记录”页面及侧栏/设置入口已删除。注册表缓存版本为 registry_cleanable_v5。

## 与管家功能的证据边界

复用先前 REA 保存的腾讯 18.1.30302.212 脚本分析：RegMissFonts、RegCleanSharedDLLs、RegCleanPopMenuApplication、RegCleanAppPath、RegCleanRun 等存在相应检查入口。腾讯 RegCleanContextMenu 主要涉及 ContextMenuHandlers/CLSID；本项目没有复制这一整键/COM 判定，而独立实现更窄的失效 shell 命令值规则。共享库只清零引用且文件确定缺失，较其静态观察范围更窄。常量与调用名证明能力存在，不代表每次用户扫描实际启用、推荐选择或完整删除策略。

微软 3.23.0.0 全面体检证据未证明独立通用注册表清理；不宣称本项目和微软有同等注册表引擎。系统设置保留有用入口，不把浏览器、PDF 或用户偏好当故障。

原始腾讯静态结果保存在本会话可视化目录 Reg*.luac.json 与 GarbageClearV2.decoded.xml；不作为产品依赖，不复制私有规则、DLL、服务或驱动。

## 验证

只读本机集成成功返回 50 个逻辑根，结果包括既有 MUI/程序路径及新增打开方式/右键命令；未执行真实注册表删除或恢复。隔离测试验证根/类型/零引用边界、扫描与删除共用目标解析、逐值备份优先、无递归整键删除、默认折叠与跨类别选择。
