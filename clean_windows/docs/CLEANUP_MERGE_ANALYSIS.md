# 微软空间清理与腾讯垃圾清理：REA 逻辑对照及合并

本轮分析：2026-10-21 至 2026-10-22。本机目标：微软电脑管家 3.23.0.0，腾讯电脑管家 18.1.30302.212。独立实现功能，不复制或依赖其私有 DLL、驱动、脚本和整包规则库。

## 一、微软：全面体检 → 空间清理

### 实际调用链

1. `HCCleanTrashService.InitializeAsync` 激活清理插件；`CheckAsync` 构造 ScanRequest，设置报告/不可移除筛选相关头，调用 `OpenSessionAsync → ScanningAsync`。
2. 插件用场景 ID、配置版本和 TaskSessionId 固定本次规则上下文。场景、条目、规则分别由 worker 执行，进度转换为场景/条目状态。主界面把总字节数、数量、每项选择与状态显示出来。
3. `CleanTrashOptionsDefault.HealthCheck` 的六个内置条目及引用规则见下表。其他 DeepClean 场景与体检场景不同，不能把整个插件的所有能力都算作此入口。
4. `DirectoryRule` 指定根路径模式、文件名模式、搜索深度、时间限制和运行权限；支持注册表、INI、JSON、用户变量等路径来源。默认配置还可由本地/更新配置装载器替换，故内置默认不等于当前线上/用户实际生效配置。
5. `DirTrashScanRuleExecutor.Traverse` 组合文件名、时间、系统/隐藏属性和 NotRemovableFilter 等过滤；结果转为清理规则/文件实体。`FileTimeFilter` 实际读取 LastWriteTimeUtc 和 CreationTimeUtc，不能仅按字段名 LastAccess 宣称采用最后访问时间。
6. `NotRemovableFilter` 是有期限的不可移除路径缓存（字典、过期时间、Add/Clear/IsMatch），不等同于主动证明所有文件当前可删。场景还有前置条件、进程信息、已清理条目过滤，以及服务/用户进程权限分工。
7. `RepairAsync` 传相同配置版本和会话到 CleaningAsync。目录/文件执行器经 SafeDelete 处理已扫描文件实体，逐项记录 Deleted/DeleteFailCode、取消、异常、清理记录与统计；系统项有 IEmptyVolumeCache 类插件路径。最后 CloseSessionAsync 释放上下文。

### 体检内置分类（静态观察）

| 内置项 | 实际规则 ID | 目标 |
| --- | --- | --- |
| Windows 缓存 HCWindowsCache | software_distribution_1 | Windows/SoftwareDistribution/Download |
| 上网垃圾 HCWebTrash | web_cache_1、2、3 | 用户 INetCache/IE、WebCache、WebCache.old |
| 临时文件 HCTempFiles | temp_1、2 | 用户 Local/Temp、Windows/Temp |
| 系统垃圾 HCSystemTrash | wer_report_1—4、crash_dump_1—3 | 用户/系统 WER ReportArchive/ReportQueue、用户 CrashDumps、Windows 根 *.dmp、Minidump |
| 系统日志 HCSystemLog | software_distribution_2、windows_log_1、2 | SoftwareDistribution/DataStore/Logs 的 *.jrs/*.log、System32/LogFiles、Windows/Logs |
| 最近文件 HCRecentFiles | recent_1 | 用户 Recent 的 *.lnk |

`HealthCheck` 方法中六个 NewItemOption 调用的布尔选择参数均为 true（CIL ldc.i4.1，经参数位置与 set_IsSelected 追踪）。这只证明**内置构造默认值**，没有验证当前用户历史选择、更新配置或实际界面状态；CleanWin 不跟随该选择策略。

### REA 证据

- 体检入口主程序集：`ev_12f3b4f55548826419edb8c6754c4ff532ef0bce9b05ed488f539d1f4dec0d49`。SHA-256 `29adf3e1fc545ef066a6b225d0af94b2159313f15c173d289fa75408ae1ec6f0`，MVID `a8b819aa-bfa2-48fb-9ed6-359e5c2561ce`。
- CleanTrash 插件成员/worker：`ev_a6986a8e203fcca81d940cfef1ed9186f01b3131f51ce3a5c78e367fa2ab0152`。
- Executor 扫描、过滤、删除：`ev_54d7b2e9cf6225ee0db7a040a1e8a872afe3ba235d5b29630ff034b16b73a1b7`。SHA-256 `a0dbfa9569d6dfeda6e9aa2131d70797fee1803bd4346aa952d82b8595b96dc3`，MVID `3ac6ba02-ad9a-4d7c-ab83-8fb465f49614`。
- Options 默认场景与规则：`ev_899c8817966062f9d805295a8aadf2cb2f5e40c53a503a1082b0596484c11faf`。
- 完整输出：本次 Codex 可视化目录 `merge-microsoft/space-cleanup-evidence.json`，并复用 `microsoft/healthcheck-evidence.json`。其中原始元数据 token 仅对记录的 SHA-256/MVID 有效。

## 二、腾讯：垃圾清理

1. `CScanDataMgr::Load` 装载 GarbageClearV2.dat，QMCommon 解码后解析分类、软件条目、位置、过滤和动作。主库规则版本 2026091700，七类为 Windows、上网、视频音乐、聊天软件、常用软件、注册表、网络游戏垃圾。
2. 清理引擎同时加载 QMScriptHost 与 GarbageCleanerScript.dat，注册 AddScanPath、AddScanFileResult、AddScanRegResult、AddScanRegValueResult、IsPause、IsCancle。软件脚本从注册表、INI、目录变量等发现动态路径，再回送扫描引擎。
3. 规则条件包括 OS、位置层数、名称/后缀/路径、时间、大小、排除条件、运行进程和服务状态；卸载残留脚本还核验 32/64 位注册表与程序是否仍存在，不能把软件目录名直接当成缓存。
4. 运行状态确实影响 CAtomFile::Scan，但 IsProcRunning 的模式可能跳过、记录锁定状态或继续后续处理，**不是所有运行程序都统一跳过**。本轮没有移植可能的进程处置、强制关闭或服务控制。
5. 静态库有 3745 个直接 item；其中 recommend=true 2787、false 958，另有 caution/fastmode/quickmode/depthclean 等标记。它们是条件库条目数，不是当前电脑的垃圾数。GetItemSelectState 读取层级条目选择属性，但未穷尽 UI 初始化和历史/云策略覆盖，不能把 recommend 等同于当前界面默认勾选。
6. 下载规则包含多个时间/大小分支，部分名称与常量不一致，还混用访问/修改时间接口；CleanWin 按明确最后修改时间展示，不照搬有歧义的标签。
7. 配置解析包含清理动作，且脚本可取消/暂停；本轮没有穷尽腾讯每类删除动作、回收站/强删及失败恢复的全部运行行为，不能宣称其全部删除可恢复。

### 腾讯 REA 证据

- 脚本回调注册：`ev_d72edac8828520c2e49113bece98592fa97c4214cf0f06f5e6f10f90be7d49f4`。
- 选择状态：`ev_e7b81c021c22189e8c38750020c82306a5bcd4ef4bfb548b0cde200aa07ac1b0`。
- 本轮 CAtomFile::Scan：`ev_82245b29decd2a5b5da7cbee42e752d86f0e2edf04bd1aa1e4ef843ebc5bb013`。
- IsProcRunning：`ev_09101f8d00168b4c70276bf5a6ce5812b3d1bbad2debd229761f4f259616cd31`。
- CRunFilter::CheckRunning：`ev_a87d08f39aa8759ab2b9947aae70e9b381fef8dab74f0a2df5e354501e4c8522`。
- 规则路径的证据是已静态解码 XML 的 item/location/filter ID，见下表与本次可视化目录 `merge-tencent/窄范围规则候选.md`；该目录保留原生 REA 输出、静态计数与有边界的结论。

## 三、合并到 CleanWin 的实际行为

| 共用能力 | 现有功能及本次落地 |
| --- | --- |
| 同一清理流程 | 概览新增“空间清理”；全面体检加入同名面板；两处调用 AppState.scanSpaceCleanup，共享结果、选择、字节数、取消、白名单与文件快照；查看/执行仍用现有概览确认和成功反馈 |
| 范围分层 | 保留原日常一键扫描；显式空间扫描额外包含旧系统日志、七天前的崩溃转储和使用痕迹。软件缓存保持窄路径快速发现；除非用户已启用深度模式，不遍历整个软件目录 |
| 权限与占用 | 仍逐文件验证可操作性；无法读取/删除的内容不强制纳入；不借用两家服务提升权限，不结束程序 |
| 去重与所有权 | 规范路径在各分类间去重。专属窄规则先处理并拥有其路径，阻止通用深扫再次扩大范围；WER 中转储由转储分类先拥有，报告与配置分开 |
| 风险与默认值 | 只有旧的、可操作的 .tmp/.temp 临时文件自动选；GPU、软件/浏览器缓存、下载、回收站、旧日志、转储、痕迹及新增规则仍手动选；说明排障数据与固定跳转项的影响 |
| WER 精度 | 从整个 WER 根收窄到 ReportArchive/ReportQueue，报告至少七天；不读取/清理 WER Settings 等配置树 |
| Explorer 精度 | 图标/缩略图仅当前层明确 .db；待删除目录单独匹配 thm*.tmp/icn*.tmp，不扩大到旁边 .txt 或子目录 |
| 重扫体验 | 开始重新扫描不清空已有结果；按完成分类替换；取消保留尚未替换的旧分类。清理仍按文件签名、白名单和链接状态二次核验 |
| 本地缓存版本 | 扫描缓存升级到 results_v8_space_merge，避免恢复此前广范围旧快照 |
| 系统维护 | 提供 Windows 清理入口，启动系统 cleanmgr.exe，由 Windows 展示并处理版本支持的维护项；应用不直接删除组件、更新数据库或强停服务 |

### 本次新增的精确路径规则

全部在 cleanup_rules.dart 自主维护，默认不选，继续经过相同白名单、链接、文件签名、可操作性与去重流程。

| 来源 | 范围 | 过滤 |
| --- | --- | --- |
| 腾讯 item183/location2709/filter2055 | Local/Microsoft/Windows/Explorer/ThumbCacheToDelete | 当前层 thm*.tmp |
| 腾讯 item183/location41241/filter3507 | Local/Microsoft/Windows/Explorer/IconCacheToDelete | 当前层 icn*.tmp；原过滤器列语义有歧义，本项目独立收窄为 basename 匹配 |
| 腾讯 item233/location11633/filter1135 | Local/Microsoft/Terminal Server Client/Cache | 当前层 .bmc，不含连接配置 |
| 腾讯 item149/location33030、33031/filter62 | Local/Microsoft/clr_v4.0、clr_v4.0_32 | 当前层、七天前 .log，不含运行时程序集 |
| 腾讯 item42507/location42508 | 指定 Windows 小组件包 Default/Cache | f_、data_ 前缀或精确 index；不扩大为包目录 |
| 腾讯 item42507/location42511/filter3210 | 同一小组件 Default/Code Cache | *_0，不处理存储/会话/GPU |
| 微软 HealthCheck/web_cache_3 | Local/Microsoft/Windows/WebCache.old | 七天前文件；不处理正在使用的 WebCache 数据库 |

此前已加入的国产浏览器、多用户配置、迅雷/浏览器自定义下载、小文件展示、腾讯/.NET/IIS 日志及图标/字体/证书缓存继续复用，不重复算成本轮新增。

## 四、没有照搬的高风险或未知部分

- 微软默认选择、腾讯 recommend=true 不作为本项目自动勾选依据。
- 合并入口不直接清理 SoftwareDistribution/DataStore、WinSxS、Installer、驱动包、NativeImages 及安装依赖，也不默认启用预读取清理，不调用私有服务或系统项 COM 清理接口；系统维护通过 Windows 工具处理。
- 不清浏览器 Sessions、Extension State、Cookie、密码、离线缓存和聊天记录；不按媒体目录名删除离线下载。
- 注册表仍由当前独立的可验证失效项逻辑处理，不整合腾讯 COM/ActiveX/共享 DLL 等大范围清理。
- 未证明软件已卸载时不扩大残留删除；不把所有 XML 路径硬导入。
- 继续支持取消；本次没有新增暂停/继续，也没有声称完整复制腾讯的进程处置和失败恢复策略。
- 分析是 shipped-artifact 静态元数据、CIL、原生伪码及规则观察，未对两家软件执行实际扫描/删除，也未验证云端配置和所有 UI 分支。上述限制均保留，合并不等于两家产品功能总量等价。

## 验证记录

新建隔离测试核对窄规则、后缀/文件名/年龄、深扫不扩大范围、白名单、拒绝访问过滤、去重、文件快照清理及受保护相邻文件仍存在；真实用户文件没有被扫描或清理。另验证两入口共享选择大小、重扫保留、取消保留与原有清理交互。

最终结果：`dart analyze lib test` 无问题；71 项相关行为回归通过。另在开启 UI_PREVIEWS 的隔离运行中，5 项合并行为测试及 2 项宽窄截图测试通过，导出结果/扫描/取消状态供核对。普通热重载因 const 规则类结构变化被 Flutter 拒绝，随后通过 Flutter Manager 热重启，控制台确认 `Restarted application in 1,272ms`。未执行真实文件清理，也未在验证中启动 Windows 磁盘清理。

后续界面整合（2026-10-22）：已将独立全面体检入口合入概览；主扫描统一执行空间和本机体检。空间分类、大小、文件数量与明细直接列在概览结果中，电脑体检默认折叠。保留单独确认的系统维护操作。
