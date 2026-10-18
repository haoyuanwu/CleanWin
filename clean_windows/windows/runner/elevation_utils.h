#ifndef RUNNER_ELEVATION_UTILS_H_
#define RUNNER_ELEVATION_UTILS_H_

#include <windows.h>
#include <sddl.h>
#include <string>
#include <vector>

inline bool IsProcessElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
  TOKEN_ELEVATION elevation = {};
  DWORD size = 0;
  const bool ok = GetTokenInformation(token, TokenElevation, &elevation,
                                      sizeof(elevation), &size) != FALSE;
  CloseHandle(token);
  return ok && elevation.TokenIsElevated != 0;
}

inline std::wstring CurrentUserSid() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return {};
  DWORD size = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<BYTE> buffer(size);
  std::wstring sid;
  if (size && GetTokenInformation(token, TokenUser, buffer.data(), size, &size)) {
    LPWSTR text = nullptr;
    if (ConvertSidToStringSidW(
            reinterpret_cast<TOKEN_USER*>(buffer.data())->User.Sid, &text)) {
      sid = text;
      LocalFree(text);
    }
  }
  CloseHandle(token);
  return sid;
}

#endif
