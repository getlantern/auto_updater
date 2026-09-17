#include "auto_updater.h"

#include "winsparkle.h"

#include <stdexcept>

#if !WIN_SPARKLE_CHECK_VERSION(0, 9, 4)
#error "auto_updater_windows requires WinSparkle 0.9.4 or newer"
#endif

namespace auto_updater_windows {
namespace {
constexpr wchar_t kWindowClass[] = L"AutoUpdaterEvents";
constexpr UINT kDispatchEvents = WM_APP + 1;
using flutter::EncodableMap;
using flutter::EncodableValue;
}  // namespace

AutoUpdater* AutoUpdater::instance_ = nullptr;

AutoUpdater::AutoUpdater() {
  if (instance_ != nullptr) {
    throw std::logic_error("AutoUpdater has already been initialized");
  }
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kWindowClass;
  if (!RegisterClassW(&window_class) &&
      GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    throw std::runtime_error("Could not register updater event window");
  }
  window_ = CreateWindowExW(0, kWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                            nullptr, window_class.hInstance, this);
  if (!window_) {
    throw std::runtime_error("Could not create updater event window");
  }
  instance_ = this;
}

AutoUpdater::~AutoUpdater() {
  // Stop WinSparkle's threads before releasing their callback target.
  if (initialized_) {
    win_sparkle_cleanup();
  }
  win_sparkle_set_error_callback(nullptr);
  win_sparkle_set_shutdown_request_callback(nullptr);
  win_sparkle_set_did_find_update_callback(nullptr);
  win_sparkle_set_did_not_find_update_callback(nullptr);
  win_sparkle_set_update_cancelled_callback(nullptr);
  instance_ = nullptr;
  DestroyWindow(window_);
  UnregisterClassW(kWindowClass, GetModuleHandle(nullptr));
}

void AutoUpdater::SetFeedURL(const std::string& feed_url) {
  win_sparkle_set_appcast_url(feed_url.c_str());
  if (initialized_) {
    return;
  }
  win_sparkle_set_error_callback(OnError);
  win_sparkle_set_shutdown_request_callback(OnShutdownRequest);
  win_sparkle_set_did_find_update_callback(OnDidFindUpdate);
  win_sparkle_set_did_not_find_update_callback(OnDidNotFindUpdate);
  win_sparkle_set_update_cancelled_callback(OnUpdateCancelled);
  initialized_ = true;
  win_sparkle_init();
}

void AutoUpdater::CheckForUpdates() {
  EmitEvent("checking-for-update");
  win_sparkle_check_update_with_ui();
}

void AutoUpdater::CheckForUpdatesWithoutUI() {
  EmitEvent("checking-for-update");
  win_sparkle_check_update_without_ui();
}

void AutoUpdater::SetScheduledCheckInterval(int interval) {
  win_sparkle_set_update_check_interval(interval);
}

void AutoUpdater::RegisterEventSink(
    std::unique_ptr<flutter::EventSink<EncodableValue>> sink) {
  std::lock_guard<std::mutex> lock(events_mutex_);
  pending_events_ = {};
  event_sink_ = std::move(sink);
}

void AutoUpdater::EmitEvent(const std::string& type, const EncodableMap& data) {
  std::lock_guard<std::mutex> lock(events_mutex_);
  if (!event_sink_) {
    return;
  }
  pending_events_.emplace(EncodableMap{
      {EncodableValue("type"), EncodableValue(type)},
      {EncodableValue("data"), EncodableValue(data)},
  });
  // WinSparkle callbacks can run on worker threads; Flutter events cannot.
  PostMessage(window_, kDispatchEvents, 0, 0);
}

void AutoUpdater::DispatchEvents() {
  std::queue<EncodableValue> events;
  {
    std::lock_guard<std::mutex> lock(events_mutex_);
    events.swap(pending_events_);
  }
  while (!events.empty()) {
    if (event_sink_) {
      event_sink_->Success(events.front());
    }
    events.pop();
  }
}

LRESULT CALLBACK AutoUpdater::WindowProc(HWND window,
                                         UINT message,
                                         WPARAM wparam,
                                         LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* creation = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(creation->lpCreateParams));
  } else if (message == kDispatchEvents) {
    auto* updater =
        reinterpret_cast<AutoUpdater*>(GetWindowLongPtr(window, GWLP_USERDATA));
    updater->DispatchEvents();
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void AutoUpdater::OnError() {
  // WinSparkle's error callback has no code or message parameters.
  const EncodableMap data{
      {EncodableValue("error"),
       EncodableValue("WinSparkle could not complete the update.")},
      {EncodableValue("errorDomain"), EncodableValue("WinSparkle")},
  };
  instance_->EmitEvent("error", data);
  instance_->EmitEvent("update-cycle-finished", data);
}

void AutoUpdater::OnShutdownRequest() {
  instance_->EmitEvent("update-cycle-finished");
  instance_->EmitEvent("before-quit-for-update");
}

void AutoUpdater::OnDidFindUpdate() {
  instance_->EmitEvent("update-available");
}

void AutoUpdater::OnDidNotFindUpdate() {
  instance_->EmitEvent("update-not-available");
  instance_->EmitEvent("update-cycle-finished");
}

void AutoUpdater::OnUpdateCancelled() {
  instance_->EmitEvent("update-cancelled");
  instance_->EmitEvent("update-cycle-finished");
}

}  // namespace auto_updater_windows
