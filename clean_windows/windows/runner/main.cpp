#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "elevation_utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // The embedded manifest requests UAC before entry. Refuse to scan if a
  // modified launcher or executable strips that requirement.
  if (!IsProcessElevated()) {
    MessageBoxW(nullptr,
        L"CleanWin 需要管理员权限才能读取系统清理目录。\n"
        L"请允许 Windows 管理员授权，或以管理员身份启动程序。",
        L"CleanWin - 需要管理员权限", MB_OK | MB_ICONWARNING);
    return ERROR_ELEVATION_REQUIRED;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Never silently switch the scanned profile when UAC uses another account.
  const std::string prefix = "--cleanwin-admin-scan=";
  for (const auto& argument : command_line_arguments) {
    if (argument.rfind(prefix, 0) != 0) continue;
    const auto sid = CurrentUserSid();
    std::string ascii_sid;
    for (const wchar_t character : sid) {
      ascii_sid.push_back(static_cast<char>(character));
    }
    if (!IsProcessElevated() || sid.empty() ||
        argument.substr(prefix.size()) != ascii_sid) {
      MessageBoxW(nullptr,
          L"请使用当前账号的管理员授权。使用其他账号会改变扫描的用户目录，"
          L"本次扫描未启动，原窗口和结果已保留。",
          L"CleanWin - 无法启动管理员扫描", MB_OK | MB_ICONINFORMATION);
      CoUninitialize();
      return EXIT_FAILURE;
    }
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"CleanWin", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
