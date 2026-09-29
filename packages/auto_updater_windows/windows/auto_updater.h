#ifndef FLUTTER_PLUGIN_AUTO_UPDATER_H_
#define FLUTTER_PLUGIN_AUTO_UPDATER_H_

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/event_sink.h>

#include <memory>
#include <mutex>
#include <queue>
#include <string>

namespace auto_updater_windows {

class AutoUpdater {
 public:
  AutoUpdater();
  ~AutoUpdater();

  AutoUpdater(const AutoUpdater&) = delete;
  AutoUpdater& operator=(const AutoUpdater&) = delete;

  void SetFeedURL(const std::string& feed_url);
  void CheckForUpdates();
  void CheckForUpdatesWithoutUI();
  void SetScheduledCheckInterval(int interval);
  void RegisterEventSink(
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink);

 private:
  static LRESULT CALLBACK WindowProc(HWND window,
                                     UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam);
  static void OnError();
  static void OnShutdownRequest();
  static void OnDidFindUpdate();
  static void OnDidNotFindUpdate();
  static void OnUpdateCancelled();

  void EmitEvent(const std::string& type,
                 const flutter::EncodableMap& data = {});
  void DispatchEvents();

  static AutoUpdater* instance_;
  HWND window_ = nullptr;
  bool initialized_ = false;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  std::mutex events_mutex_;
  std::queue<flutter::EncodableValue> pending_events_;
};

}  // namespace auto_updater_windows

#endif  // FLUTTER_PLUGIN_AUTO_UPDATER_H_
