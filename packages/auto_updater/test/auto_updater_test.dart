import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:auto_updater_platform_interface/auto_updater_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestPlatform extends AutoUpdaterPlatform {
  final events = StreamController<Map<Object?, Object?>>.broadcast(sync: true);

  @override
  Stream<Map<Object?, Object?>> get sparkleEvents => events.stream;
}

// Keep an implements-based consumer here: adding methods to UpdaterListener
// would break existing applications even if those methods had default bodies.
class _Listener implements UpdaterListener {
  final calls = <String>[];
  final errors = <UpdaterError?>[];
  Appcast? appcast;
  AppcastItem? item;

  @override
  void onUpdaterError(UpdaterError? error) {
    calls.add('error');
    errors.add(error);
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    calls.add('checking');
    this.appcast = appcast;
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    calls.add('available');
    item = appcastItem;
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    calls.add('no-update');
    errors.add(error);
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    calls.add('downloaded');
    item = appcastItem;
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    calls.add('quit');
    item = appcastItem;
  }
}

class _LifecycleListener extends _Listener with UpdaterLifecycleListener {
  @override
  void onUpdaterUpdateCancelled() => calls.add('cancelled');

  @override
  void onUpdaterUpdateCycleFinished(UpdaterError? error) {
    calls.add('finished');
    errors.add(error);
  }
}

class _RemovingListener extends _Listener {
  @override
  void onUpdaterError(UpdaterError? error) {
    super.onUpdaterError(error);
    autoUpdater.removeListener(this);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = _TestPlatform();
  late _Listener legacy;
  late _LifecycleListener lifecycle;

  void emit(String type, [Map<String, Object?>? data]) {
    platform.events.add({'type': type, if (data != null) 'data': data});
  }

  setUpAll(() => AutoUpdaterPlatform.instance = platform);
  tearDownAll(platform.events.close);

  setUp(() {
    legacy = _Listener();
    lifecycle = _LifecycleListener();
    autoUpdater.addListener(legacy);
    autoUpdater.addListener(lifecycle);
  });

  tearDown(() {
    autoUpdater.removeListener(legacy);
    autoUpdater.removeListener(lifecycle);
  });

  test('preserves native error details and the existing string representation',
      () {
    emit('error', {
      'error': 'Could not download the update.',
      'errorCode': 2001,
      'errorDomain': 'SUSparkleErrorDomain',
    });

    final error = legacy.errors.single!;
    expect(error.code, 2001);
    expect(error.domain, 'SUSparkleErrorDomain');
    expect(error.toString(), 'UpdaterError: Could not download the update.');
    expect(UpdaterError('old constructor').message, 'old constructor');
  });

  test('accepts error payloads from older native plugins', () {
    emit('error', {'error': 'Old error'});
    emit('error');

    expect(legacy.errors.first!.message, 'Old error');
    expect(legacy.errors.first!.code, isNull);
    expect(legacy.errors.first!.domain, isNull);
    expect(legacy.errors.last, isNull);
  });

  test('no update preserves diagnostics without invoking the failure callback',
      () {
    emit('update-not-available', {
      'error': 'You are up to date.',
      'errorCode': 1001,
      'errorDomain': 'SUSparkleErrorDomain',
    });
    emit('update-cycle-finished');

    expect(legacy.calls, ['no-update']);
    expect(legacy.errors.single!.code, 1001);
    expect(lifecycle.calls, ['no-update', 'finished']);
    expect(lifecycle.errors.last, isNull);
  });

  test('lifecycle callbacks are opt-in and preserve failure details', () {
    emit('update-cancelled');
    emit('update-cycle-finished');
    emit('update-cycle-finished', {
      'error': 'Network unavailable',
      'errorCode': -1009,
      'errorDomain': 'NSURLErrorDomain',
    });

    expect(legacy.calls, isEmpty);
    expect(lifecycle.calls, ['cancelled', 'finished', 'finished']);
    expect(lifecycle.errors.first, isNull);
    expect(lifecycle.errors.last!.code, -1009);
  });

  test('accepts the cancellation event from older Windows plugins', () {
    emit('updateCancelled');
    expect(lifecycle.calls, ['cancelled']);
    expect(legacy.calls, isEmpty);
  });

  test('preserves existing appcast and installation callbacks', () {
    final item = {
      'versionString': '42',
      'fileURL': 'https://example.com/app.exe',
    };
    emit('checking-for-update', {
      'appcast': {
        'items': [item],
      },
    });
    emit('update-available', {'appcastItem': item});
    emit('update-downloaded', {'appcastItem': item});
    emit('before-quit-for-update', {'appcastItem': item});

    expect(legacy.calls, ['checking', 'available', 'downloaded', 'quit']);
    expect(legacy.appcast!.items.single.versionString, '42');
    expect(legacy.item!.fileURL, 'https://example.com/app.exe');
  });

  test('listeners can remove themselves without interrupting delivery', () {
    final removing = _RemovingListener();
    final remaining = _Listener();
    autoUpdater.addListener(removing);
    autoUpdater.addListener(remaining);
    addTearDown(() => autoUpdater.removeListener(remaining));

    emit('error');
    emit('error');
    expect(removing.calls, ['error']);
    expect(remaining.calls, ['error', 'error']);
  });

  test('existing method channel forwards the feed URL and background mode',
      () async {
    const channel = MethodChannel('dev.leanflutter.plugins/auto_updater');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final methodChannel = MethodChannelAutoUpdater();
    await methodChannel.setFeedURL('http://127.0.0.1:8080/appcast.xml');
    await methodChannel.checkForUpdates(inBackground: true);
    expect(
      calls[0].arguments,
      {'feedURL': 'http://127.0.0.1:8080/appcast.xml'},
    );
    expect(calls[1].arguments, {'inBackground': true});
  });

  test('method channel preserves native initialization failure details',
      () async {
    const channel = MethodChannel('dev.leanflutter.plugins/auto_updater');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: '6',
        message: 'Invalid host bundle identifier',
        details: {'errorCode': 6, 'errorDomain': 'SUSparkleErrorDomain'},
      );
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await expectLater(
      MethodChannelAutoUpdater().setFeedURL('https://example.com/appcast.xml'),
      throwsA(
        isA<PlatformException>()
            .having((error) => error.code, 'code', '6')
            .having(
          (error) => error.details,
          'details',
          {'errorCode': 6, 'errorDomain': 'SUSparkleErrorDomain'},
        ),
      ),
    );
  });
}
