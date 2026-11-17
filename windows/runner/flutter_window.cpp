#include "flutter_window.h"

#include <flutter_windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Where the window placement is kept between starts.
constexpr wchar_t kSettingsKey[] = L"Software\\anatosun\\Puffer";
constexpr wchar_t kPlacementValue[] = L"WindowPlacement";

// The smallest window that still fits the phone layout, in logical pixels.
constexpr int kMinWidth = 400;
constexpr int kMinHeight = 560;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  RestorePlacement();

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (maximized_) {
      ::ShowWindow(GetHandle(), SW_SHOWMAXIMIZED);
    } else {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RestorePlacement() {
  WINDOWPLACEMENT placement = {};
  DWORD size = sizeof(placement);
  if (::RegGetValueW(HKEY_CURRENT_USER, kSettingsKey, kPlacementValue,
                     RRF_RT_REG_BINARY, nullptr, &placement,
                     &size) != ERROR_SUCCESS ||
      size != sizeof(placement) || placement.length != sizeof(placement)) {
    return;
  }
  // A window on a screen that is gone stays where Windows puts it.
  if (!::MonitorFromRect(&placement.rcNormalPosition, MONITOR_DEFAULTTONULL)) {
    return;
  }
  maximized_ = placement.showCmd == SW_SHOWMAXIMIZED;
  // The window shows with the first frame.
  placement.showCmd = SW_HIDE;
  ::SetWindowPlacement(GetHandle(), &placement);
}

void FlutterWindow::SavePlacement() {
  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(placement);
  if (!::GetWindowPlacement(GetHandle(), &placement)) {
    return;
  }
  ::RegSetKeyValueW(HKEY_CURRENT_USER, kSettingsKey, kPlacementValue,
                    REG_BINARY, &placement, sizeof(placement));
}

void FlutterWindow::OnDestroy() {
  SavePlacement();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_GETMINMAXINFO: {
      auto info = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = FlutterDesktopGetDpiForHWND(hwnd);
      info->ptMinTrackSize.x = ::MulDiv(kMinWidth, dpi, 96);
      info->ptMinTrackSize.y = ::MulDiv(kMinHeight, dpi, 96);
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
