#include "auto_updater_windows_plugin.h"
#include "winsparkle.h"

#include <flutter/method_result_functions.h>
#include <gtest/gtest.h>

#include <thread>
#include <vector>

namespace {
win_sparkle_error_callback_t error_callback;
win_sparkle_shutdown_request_callback_t shutdown_callback;
win_sparkle_did_find_update_callback_t found_callback;
win_sparkle_did_not_find_update_callback_t not_found_callback;
win_sparkle_update_cancelled_callback_t cancelled_callback;
int init_count;
int cleanup_count;
std::string feed_url;
bool fail_on_init;
int automatic_checks;
int check_interval;
}  // namespace

// Replace only the SDK boundary; event delivery uses a real Windows message
// loop.
extern "C" {
void win_sparkle_set_appcast_url(const char* url) {
  feed_url = url;
}
void win_sparkle_init() {
  ++init_count;
  ASSERT_NE(error_callback, nullptr);
  ASSERT_NE(shutdown_callback, nullptr);
  ASSERT_NE(found_callback, nullptr);
  ASSERT_NE(not_found_callback, nullptr);
  ASSERT_NE(cancelled_callback, nullptr);
  if (fail_on_init)
    error_callback();
}
void win_sparkle_cleanup() {
  ++cleanup_count;
}
void win_sparkle_set_error_callback(win_sparkle_error_callback_t cb) {
  error_callback = cb;
}
void win_sparkle_set_shutdown_request_callback(
    win_sparkle_shutdown_request_callback_t cb) {
  shutdown_callback = cb;
}
void win_sparkle_set_did_find_update_callback(
    win_sparkle_did_find_update_callback_t cb) {
  found_callback = cb;
}
void win_sparkle_set_did_not_find_update_callback(
    win_sparkle_did_not_find_update_callback_t cb) {
  not_found_callback = cb;
}
void win_sparkle_set_update_cancelled_callback(
    win_sparkle_update_cancelled_callback_t cb) {
  cancelled_callback = cb;
}
void win_sparkle_check_update_with_ui() {
  not_found_callback();
}
void win_sparkle_check_update_without_ui() {
  not_found_callback();
}
void win_sparkle_set_update_check_interval(int interval) { check_interval = interval; }
void win_sparkle_set_automatic_check_for_updates(int enabled) { automatic_checks = enabled; }
}

namespace auto_updater_windows {
namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;

class RecordingSink : public flutter::EventSink<EncodableValue> {
 public:
  RecordingSink(std::vector<EncodableMap>& events, DWORD platform_thread)
      : events_(events), platform_thread_(platform_thread) {}

 protected:
  void SuccessInternal(const EncodableValue* event) override {
    EXPECT_EQ(GetCurrentThreadId(), platform_thread_);
    ASSERT_NE(event, nullptr);
    events_.push_back(std::get<EncodableMap>(*event));
  }

  void ErrorInternal(const std::string& code,
                     const std::string& message,
                     const EncodableValue* details) override {
    FAIL() << "Unexpected stream error: " << code << ": " << message;
  }

  void EndOfStreamInternal() override { FAIL() << "Unexpected end of stream"; }

 private:
  std::vector<EncodableMap>& events_;
  DWORD platform_thread_;
};

void PumpMessages() {
  MSG message;
  while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&message);
    DispatchMessage(&message);
  }
}

class AutoUpdaterWindowsTest : public ::testing::Test {
 protected:
  void SetUp() override {
    init_count = 0;
    cleanup_count = 0;
    fail_on_init = false;
    plugin = std::make_unique<AutoUpdaterWindowsPlugin>();
    Listen();
  }

  void TearDown() override {
    plugin.reset();
    PumpMessages();
  }

  void Listen() {
    plugin->OnListenInternal(
        nullptr, std::make_unique<RecordingSink>(events, platform_thread));
  }

  void SetFeed(const std::string& url = "http://127.0.0.1:8080/appcast.xml") {
    bool succeeded = false;
    plugin->HandleMethodCall(
        flutter::MethodCall<EncodableValue>(
            "setFeedURL",
            std::make_unique<EncodableValue>(EncodableMap{
                {EncodableValue("feedURL"), EncodableValue(url)}})),
        std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
            [&succeeded](const EncodableValue*) { succeeded = true; }, nullptr,
            nullptr));
    EXPECT_TRUE(succeeded);
  }

  std::vector<std::string> Types() const {
    std::vector<std::string> types;
    for (const auto& event : events) {
      types.push_back(std::get<std::string>(event.at(EncodableValue("type"))));
    }
    return types;
  }

  const DWORD platform_thread = GetCurrentThreadId();
  std::unique_ptr<AutoUpdaterWindowsPlugin> plugin;
  std::vector<EncodableMap> events;
};

TEST_F(AutoUpdaterWindowsTest, ReceivesErrorsDuringInitialization) {
  fail_on_init = true;
  SetFeed();
  EXPECT_TRUE(events.empty());
  PumpMessages();
  EXPECT_EQ(Types(),
            (std::vector<std::string>{"error", "update-cycle-finished"}));
  const auto& data =
      std::get<EncodableMap>(events[0].at(EncodableValue("data")));
  EXPECT_FALSE(std::get<std::string>(data.at(EncodableValue("error"))).empty());
  EXPECT_EQ(data.count(EncodableValue("errorCode")), 0u);
  EXPECT_EQ(events[0].at(EncodableValue("data")),
            events[1].at(EncodableValue("data")));
}

TEST_F(AutoUpdaterWindowsTest, ZeroIntervalDisablesNativeScheduling) {
  for (const int interval : {7200, 0}) {
    plugin->HandleMethodCall(
        flutter::MethodCall<EncodableValue>(
            "setScheduledCheckInterval",
            std::make_unique<EncodableValue>(EncodableMap{
                {EncodableValue("interval"), EncodableValue(interval)}})),
        std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
            [](const EncodableValue*) {}, nullptr, nullptr));
    EXPECT_EQ(automatic_checks, interval > 0);
    EXPECT_EQ(check_interval, 7200);
  }
}

TEST_F(AutoUpdaterWindowsTest, ReconfiguringFeedPreservesSubscription) {
  SetFeed();
  SetFeed("http://127.0.0.1:8080/another.xml");
  EXPECT_EQ(init_count, 1);
  EXPECT_EQ(feed_url, "http://127.0.0.1:8080/another.xml");
  std::thread callback([] { not_found_callback(); });
  callback.join();
  EXPECT_TRUE(events.empty());
  PumpMessages();
  EXPECT_EQ(Types(), (std::vector<std::string>{"update-not-available",
                                               "update-cycle-finished"}));
  EXPECT_TRUE(
      std::get<EncodableMap>(events[1].at(EncodableValue("data"))).empty());
}

TEST_F(AutoUpdaterWindowsTest, CancellationAndInstallerHandoffFinishTheCycle) {
  SetFeed();
  found_callback();
  cancelled_callback();
  shutdown_callback();
  PumpMessages();
  EXPECT_EQ(Types(),
            (std::vector<std::string>{
                "update-available", "update-cancelled", "update-cycle-finished",
                "update-cycle-finished", "before-quit-for-update"}));
}

TEST_F(AutoUpdaterWindowsTest,
       CancellationDropsQueuedEventsAndAllowsResubscription) {
  SetFeed();
  error_callback();
  plugin->OnCancelInternal(nullptr);
  found_callback();
  Listen();
  PumpMessages();
  EXPECT_TRUE(events.empty());
  not_found_callback();
  PumpMessages();
  EXPECT_EQ(Types(), (std::vector<std::string>{"update-not-available",
                                               "update-cycle-finished"}));
}

TEST_F(AutoUpdaterWindowsTest, DestructionCleansUpAndAllowsAnotherInstance) {
  SetFeed();
  error_callback();
  plugin.reset();
  PumpMessages();
  EXPECT_TRUE(events.empty());
  EXPECT_EQ(cleanup_count, 1);
  EXPECT_EQ(error_callback, nullptr);
  plugin = std::make_unique<AutoUpdaterWindowsPlugin>();
  Listen();
  SetFeed();
  EXPECT_EQ(init_count, 2);
}

}  // namespace
}  // namespace auto_updater_windows
