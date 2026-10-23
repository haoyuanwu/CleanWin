# 安装与运行权限

CleanWin 整个应用要求管理员身份，安装与卸载也使用管理员权限。未同意 Windows UAC 授权时不启动程序，不降低权限继续扫描。

## 实现

- `windows/runner/runner.exe.manifest` 嵌入 `requireAdministrator`、`uiAccess=false`，覆盖 Debug / Profile / Release；快捷方式和直接打开 EXE 都遵循该清单。
- `main.cpp` 在创建 Flutter 引擎和窗口之前检查实际进程令牌，未提升则提示并退出，防止清单失效后以普通身份扫描。
- 原有显式管理员扫描参数仍校验用户 SID，不允许静默切换到其他账号的目录。
- `packaging/windows/cleanwin.iss` 使用 `PrivilegesRequired=admin`，不提供按用户安装的降权选项；安装到 Program Files，卸载器继承管理员要求。
- 安装完成启动使用 `runascurrentuser`，继承安装器的管理员令牌。
- `run.ps1` 要求管理员终端；Flutter Manager 调试也应以管理员身份启动，否则 CreateProcess 可能返回 740（需要提升）。

## 构建和打包

1. 通过 Flutter Manager 构建 Windows Release。
2. 安装 Inno Setup 6.3+ 后，执行 `powershell -File scripts/package-windows.ps1`。
3. 打包脚本先以只读资源方式检查 EXE 的嵌入式管理员清单，再编译安装包至 `dist`。可用 `-IsccPath` 指定编译器。
4. 单独检查已有构建：`powershell -File scripts/Test-AdminManifest.ps1 -ExecutablePath build/windows/x64/runner/Release/clean_windows.exe`。

安装一次不等于永久跳过 UAC。以后从普通桌面启动时仍由 Windows 请求管理员授权；从已提升的进程启动则可继承权限。标准用户输入另一管理员的凭据会更换运行账户，扫描用户目录也随之变化；应使用需要清理的当前管理员账户确认授权。

管理员权限只改善权限不足导致的读取失败，不能保证读取占用、加密、离线或特别保护的文件。本变更不修改文件 ACL、不取得系统目录所有权、不停用防护、不强行解除占用，也不扩大默认清理选择范围。

参考：[Windows 管理员清单](https://learn.microsoft.com/en-us/windows/win32/secbp/running-with-administrator-privileges)、[Inno Setup 权限配置](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm)。


## 本机验证（2026-10-22）

- Windows Release 已通过 Flutter Manager 构建，真实 `clean_windows.exe` 的嵌入式清单校验通过。
- 新版运行进程的 Windows `TokenElevation` 已只读核实为已提升（管理员身份）。
- 使用本机 `C:\Program Files\Inno Setup 7\ISCC.exe`（7.1.0）成功生成 `dist/CleanWin-1.0.0-windows-x64-setup.exe`。
- 安装包已生成，未执行安装向导，也未修改系统安装登记。
- 注意：Inno Setup 的外层引导程序使用 `asInvoker` 清单，随后依据 `PrivilegesRequired=admin` 提升实际安装进程，这是编译器的正常设计。`Test-AdminManifest.ps1` 只验证 CleanWin 应用 EXE，不能用来验证 Inno 外层引导程序。参考：[Inno Setup 安全机制](https://jrsoftware.org/is6help/topic_securitymeasures.htm)。
- PowerShell 打包脚本和验证脚本语法检查通过；打包前已验证完整 Release 资源并拒绝普通权限旧构建。
