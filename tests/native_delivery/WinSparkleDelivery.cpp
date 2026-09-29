#include <windows.h>
#include <winsparkle.h>

#include <atomic>
#include <cstdio>
#include <string>

namespace {
std::atomic<int> outcome{0};
void OnError() { outcome = 2; }
void OnNoUpdate() { outcome = 3; }
int OnInstaller(const wchar_t*) {
  // WinSparkle verifies the signature before handing the file to this callback.
  outcome = 1;
  return 1;
}
}

int main(int argc, char** argv) {
  if (argc != 4) return 1;
  win_sparkle_set_app_details(L"Lantern tests", L"Delivery fixture", L"1.0.0");
  win_sparkle_set_app_build_version(L"1");
  win_sparkle_set_automatic_check_for_updates(0);
  win_sparkle_set_appcast_url(argv[1]);
  if (!win_sparkle_set_eddsa_public_key(argv[2])) return 1;
  win_sparkle_set_error_callback(OnError);
  win_sparkle_set_did_not_find_update_callback(OnNoUpdate);
  win_sparkle_set_user_run_installer_callback(OnInstaller);
  win_sparkle_init();
  win_sparkle_check_update_with_ui_and_install();
  const auto started = GetTickCount64();
  while (!outcome && GetTickCount64() - started < 45000) {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    Sleep(10);
  }
  const int result = outcome.load();
  std::printf("Native delivery outcome: %d\n", result);
  // The fixture owns no installer and never executes downloaded bytes.
  return result == (std::string(argv[3]) == "invalid" ? 2 : 1) ? 0 : 1;
}
