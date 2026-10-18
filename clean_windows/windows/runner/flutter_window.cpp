#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <strsafe.h>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"
#include "resource.h"
#include "elevation_utils.h"

namespace {
constexpr UINT kTrayCallback = WM_APP + 1;
constexpr UINT kTrayId = 1;
constexpr UINT kCmdShow = 2001;
constexpr UINT kCmdExit = 2002;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  RemoveTrayIcon();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  AddTrayIcon();

  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "clean_windows/window",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string method = call.method_name();
        HWND hwnd = GetHandle();
        if (!hwnd) {
          result->Error("NO_WINDOW", "Window not available");
          return;
        }
        if (method == "isElevated") {
          result->Success(flutter::EncodableValue(IsProcessElevated()));
        } else if (method == "restartForAdminScan") {
          if (IsProcessElevated()) {
            result->Success(flutter::EncodableValue("alreadyElevated"));
            return;
          }
          if (elevated_child_) {
            result->Error("PENDING", "An elevated launch is already pending");
            return;
          }
          const auto sid = CurrentUserSid();
          wchar_t executable[32768] = {};
          const DWORD length = GetModuleFileNameW(nullptr, executable, 32768);
          if (sid.empty() || !length || length >= 32768) {
            result->Error("IDENTITY", "Cannot determine application identity");
            return;
          }
          const std::wstring path(executable);
          const auto directory = path.substr(0, path.find_last_of(L"\\/"));
          const auto arguments = L"--cleanwin-admin-scan=" + sid;
          SHELLEXECUTEINFOW launch = {};
          launch.cbSize = sizeof(launch);
          launch.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
          launch.hwnd = hwnd;
          launch.lpVerb = L"runas";
          launch.lpFile = path.c_str();
          launch.lpParameters = arguments.c_str();
          launch.lpDirectory = directory.c_str();
          launch.nShow = SW_SHOWNORMAL;
          if (!ShellExecuteExW(&launch)) {
            const DWORD error = GetLastError();
            if (error == ERROR_CANCELLED) {
              result->Success(flutter::EncodableValue("cancelled"));
            } else {
              result->Error("LAUNCH", "Windows error " + std::to_string(error));
            }
            return;
          }
          elevated_child_ = launch.hProcess;
          result->Success(flutter::EncodableValue("launched"));
        } else if (method == "releaseAdminScanLaunch") {
          if (elevated_child_) {
            CloseHandle(elevated_child_);
            elevated_child_ = nullptr;
          }
          result->Success();
        } else if (method == "adminScanLaunchStatus") {
          if (!elevated_child_) {
            result->Success(flutter::EncodableValue("failed"));
            return;
          }
          DWORD exit_code = 0;
          bool ready = false;
          const bool running = GetExitCodeProcess(elevated_child_, &exit_code) &&
                               exit_code == STILL_ACTIVE;
          if (running) {
            struct Search { DWORD pid; bool visible; } search = {
                GetProcessId(elevated_child_), false};
            EnumWindows([](HWND candidate, LPARAM data) -> BOOL {
              auto* found = reinterpret_cast<Search*>(data);
              DWORD pid = 0;
              GetWindowThreadProcessId(candidate, &pid);
              if (pid == found->pid && IsWindowVisible(candidate) &&
                  GetPropW(candidate, L"CleanWinAdminScanReady")) {
                found->visible = true;
                return FALSE;
              }
              return TRUE;
            }, reinterpret_cast<LPARAM>(&search));
            ready = search.visible;
          }
          if (ready || !running) {
            CloseHandle(elevated_child_);
            elevated_child_ = nullptr;
          }
          result->Success(flutter::EncodableValue(
              ready ? "ready" : running ? "waiting" : "failed"));
        } else if (method == "minimize") {
          ShowWindow(hwnd, SW_MINIMIZE);
          result->Success();
        } else if (method == "maximize") {
          if (IsZoomed(hwnd)) {
            ShowWindow(hwnd, SW_RESTORE);
            result->Success(flutter::EncodableValue(false));
          } else {
            ShowWindow(hwnd, SW_MAXIMIZE);
            result->Success(flutter::EncodableValue(true));
          }
        } else if (method == "restore") {
          ShowWindow(hwnd, SW_RESTORE);
          result->Success();
        } else if (method == "close") {
          // Close button → hide to tray (not quit)
          HideToTray();
          result->Success();
        } else if (method == "hideToTray") {
          HideToTray();
          result->Success();
        } else if (method == "showWindow") {
          ShowFromTray();
          result->Success();
        } else if (method == "exitApp") {
          exiting_ = true;
          RemoveTrayIcon();
          PostMessage(hwnd, WM_CLOSE, 0, 0);
          result->Success();
        } else if (method == "startDrag") {
          ReleaseCapture();
          SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
        } else if (method == "isMaximized") {
          result->Success(flutter::EncodableValue(IsZoomed(hwnd) != 0));
        } else {
          result->NotImplemented();
        }
      });
  window_channel_ = std::move(channel);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    SetPropW(GetHandle(), L"CleanWinAdminScanReady", reinterpret_cast<HANDLE>(1));
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::AddTrayIcon() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  NOTIFYICONDATA nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = hwnd;
  nid.uID = kTrayId;
  nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid.uCallbackMessage = kTrayCallback;
  nid.hIcon = static_cast<HICON>(LoadImage(
      GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0));
  if (!nid.hIcon) {
    nid.hIcon = LoadIcon(nullptr, IDI_APPLICATION);
  }
  StringCchCopy(nid.szTip, ARRAYSIZE(nid.szTip), L"CleanWin");
  Shell_NotifyIcon(NIM_ADD, &nid);

  // Win10+ modern tooltip
  nid.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIcon(NIM_SETVERSION, &nid);

  tray_added_ = true;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) return;
  HWND hwnd = GetHandle();
  if (hwnd) {
    NOTIFYICONDATA nid = {};
    nid.cbSize = sizeof(nid);
    nid.hWnd = hwnd;
    nid.uID = kTrayId;
    Shell_NotifyIcon(NIM_DELETE, &nid);
  }
  tray_added_ = false;
}

void FlutterWindow::HideToTray() {
  HWND hwnd = GetHandle();
  if (hwnd) {
    ShowWindow(hwnd, SW_HIDE);
  }
}

void FlutterWindow::ShowFromTray() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  ShowWindow(hwnd, SW_SHOW);
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }
  SetForegroundWindow(hwnd);
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  POINT pt;
  GetCursorPos(&pt);

  HMENU menu = CreatePopupMenu();
  AppendMenu(menu, MF_STRING, kCmdShow, L"显示主窗口");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kCmdExit, L"退出");

  SetForegroundWindow(hwnd);
  const UINT cmd = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, nullptr);
  DestroyMenu(menu);

  if (cmd == kCmdShow) {
    ShowFromTray();
  } else if (cmd == kCmdExit) {
    exiting_ = true;
    RemoveTrayIcon();
    PostMessage(hwnd, WM_CLOSE, 0, 0);
  }
}

void FlutterWindow::OnDestroy() {
  if (elevated_child_) {
    CloseHandle(elevated_child_);
    elevated_child_ = nullptr;
  }
  RemovePropW(GetHandle(), L"CleanWinAdminScanReady");
  RemoveTrayIcon();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  window_channel_.reset();

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kTrayCallback) {
    switch (LOWORD(lparam)) {
      case WM_RBUTTONUP:
      case WM_CONTEXTMENU:
        ShowTrayMenu();
        return 0;
      case WM_LBUTTONDBLCLK:
      case WM_LBUTTONUP:
        ShowFromTray();
        return 0;
    }
    return 0;
  }

  // Close → hide to tray unless exiting
  if (message == WM_CLOSE && !exiting_) {
    HideToTray();
    return 0;
  }

  if (message == WM_NCHITTEST || message == WM_GETMINMAXINFO ||
      message == WM_NCCALCSIZE || message == WM_ERASEBKGND) {
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
