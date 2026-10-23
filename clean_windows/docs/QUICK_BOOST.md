# 系统监控：立即加速（2026-10-23）

## 微软管家 REA 证据

本机微软电脑管家 3.23.0.0：MSPCManager.dll SHA256 29adf3e1fc545ef066a6b225d0af94b2159313f15c173d289fa75408ae1ec6f0，PCBoost 插件 SHA256 f51b1bdf38a631aee5520e61afb4400db3284b637b999cb21329191368bd1c57。

- ev_dcc7a01046f01120b867a372907db2dbdeb2d1f12bc313578c3ee58d1a31850c：SmartCleanMemoryService.Act 调用 ISoftwarePlugin.OneKeyBoostAsync；SmartCleanTrashService 是独立清理路径。
- ev_2ef3c15bb7cf93614e49dab0082b6bf02c1ad7fc2e911cb5a07ae367a8fe6c2e：SoftwarePlugin.OneKeyBoostAsync 的异步状态机进入 BoostSoftwareFromListAsync。后者包含 BoostRPCService.PCBMemCleanAsync、Process.GetProcesses、Win32ProcessOperationWrapper.SetProcessWorkingSetSizeWrap，并取可用物理内存作为前后比较，生成 StartMemory/EndMemory/MemoryReduce 等字段。

以上证明静态调用关系，未完整恢复私有 RPC 的内核实现、所有配置分支或运行时选择；不能据此声称每次均整理所有进程或一定提高性能。没有调用微软私有服务、终止应用或修改微软文件。

## CleanWin 的独立实现

运行监控顶部“立即加速”：先选内存/临时文件，分析候选与旧临时文件大小；用户确认后执行。内存使用公开 EmptyWorkingSet，按当前用户 SID、当前会话、无主窗口、工作集至少 32 MB 筛选后台进程。跳过系统关键进程、其他用户、桌面 Shell、当前应用和辅助进程；仅使用已打开的稳定句柄，不变更权限或操作服务/驱动。每轮最多 8 秒，不自动循环整理。预览参数 false，不调用 EmptyWorkingSet；确认才传 true。

这会减少部分进程当前驻留工作集；页面可用内存增加量来自系统前后测量，不累加进程工作集当作物理释放量。共享页和并发程序会影响结果，应用重新使用时可能回升，不把操作包装为永久加速。失败不伪报成功。

临时文件限制见 SCANNER_RULES.md，复用现有安全删除，不处理下载、GPU、会话、密码、注册表或系统组件。支持取消后续步骤，当前内存调用在有界任务返回后结束；临时扫描与清理支持原有取消。界面分别呈现物理可用内存变化、磁盘已释放、回收站移动和未完成数量，不混算。

“任务与记录”页面已移除；各操作自己的状态/取消/完成反馈继续保留。注册表备份恢复仍在注册表页。

## 验证

REA 原始输出位于 .dart_tool/maintenance-rea；测试代码不实际清理本机进程。只读 MemoryBoostService.inspect 已在本机成功编译并返回候选，Trimmed 为 0；注册表真实验证只读；占用缓存测试使用系统临时目录隔离文件，锁定时可统计且不可选，解锁重扫转为可清理。加速交互测试采用模拟 runner，确认前 optimize 调用为 0。

参考：[工作集](https://learn.microsoft.com/windows/win32/memory/working-set)、[SetProcessWorkingSetSize](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-setprocessworkingsetsize)。

最终检查：dart analyze lib test 无问题；全量 250 项通过，4 项可选视觉用例跳过；单独运行维护/加速视觉用例并检查 560/1000 两种宽度。真实内存只读候选分析和注册表只读扫描通过，未对真实进程执行优化或真实注册表执行清理。
