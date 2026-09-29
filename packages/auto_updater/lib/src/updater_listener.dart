import 'package:auto_updater/auto_updater.dart';

abstract mixin class UpdaterListener {
  void onUpdaterError(UpdaterError? error);
  void onUpdaterCheckingForUpdate(Appcast? appcast);
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem);
  void onUpdaterUpdateNotAvailable(UpdaterError? error);
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem);
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem);
}

/// Optional lifecycle callbacks for an [UpdaterListener].
///
/// Use this mixin instead of [UpdaterListener] to receive these events.
abstract mixin class UpdaterLifecycleListener implements UpdaterListener {
  /// The native updater reported that the user cancelled, skipped, or dismissed
  /// an update. This is not a failure.
  void onUpdaterUpdateCancelled() {}

  /// The native update cycle ended, possibly with a failure.
  ///
  /// No update and user cancellation both finish without an error. On Windows,
  /// this also fires when the installer launches. It does not confirm that the
  /// update was installed, and delivery cannot be guaranteed during app exit.
  /// An available update alone does not finish a cycle on Windows.
  void onUpdaterUpdateCycleFinished(UpdaterError? error) {}
}
