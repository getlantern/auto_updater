> **🚀 Ship Your App Faster**: Try [Fastforge](https://fastforge.dev) - The simplest way to build, package and distribute your Flutter apps.

# auto_updater

[![pub version][pub-image]][pub-url] [![][discord-image]][discord-url]

[pub-image]: https://img.shields.io/pub/v/auto_updater.svg
[pub-url]: https://pub.dev/packages/auto_updater
[discord-image]: https://img.shields.io/discord/884679008049037342.svg
[discord-url]: https://discord.gg/zPa6EZ2jqb

This plugin allows Flutter **desktop** apps to automatically update themselves (based on [sparkle](https://sparkle-project.org/) and [winsparkle](https://winsparkle.org)).

<img src="https://raw.githubusercontent.com/leanflutter/auto_updater/main/screenshots/sparkle.png" width="732" alt="">

---

English | [简体中文](./README-ZH.md)

---

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Platform Support](#platform-support)
- [Documentation](#documentation)
- [Who's using it?](#whos-using-it)
- [API](#api)
  - [AutoUpdater](#autoupdater)
    - [Methods](#methods)
      - [setFeedURL](#setfeedurl)
      - [checkForUpdates](#checkforupdates)
      - [setScheduledCheckInterval](#setscheduledcheckinterval)
- [Related Links](#related-links)
- [License](#license)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Platform Support

| Linux | macOS | Windows |
| :---: | :---: | :-----: |
|  ➖   |  ✔️   |   ✔️    |

## Documentation

- [Quick Start](https://leanflutter.dev/documentation/auto_updater/quick-start)
- [API Reference](https://pub.dev/documentation/auto_updater/latest/auto_updater/)
- [Changelog](https://pub.dev/packages/auto_updater/changelog)

## Who's using it?

- [Biyi](https://biyidev.com/) - A convenient translation and dictionary app.

## API

<!-- README_DOC_GEN -->

### AutoUpdater

#### Methods

##### setFeedURL

Sets the url and initialize the auto updater.

##### checkForUpdates

Asks the server whether there is an update. You must call setFeedURL before using this API.

##### setScheduledCheckInterval

Sets the auto update check interval, default 86400, minimum 3600, 0 to disable update

<!-- README_DOC_GEN -->

### Update events

`UpdaterListener` remains compatible with existing implementations. To receive
cancellation and completion events, use `UpdaterLifecycleListener` instead; it
includes the existing callbacks and adds two optional methods:

```dart
@override
void onUpdaterUpdateCancelled() {
  // The user chose not to continue with this update.
}

@override
void onUpdaterUpdateCycleFinished(UpdaterError? error) {
  // A null error includes normal completion, no update, and cancellation.
}
```

`UpdaterError.code` and `UpdaterError.domain` preserve native error details when
available. WinSparkle exposes neither a code nor an error message, so Windows
reports a generic message, the `WinSparkle` domain, and a null code. The existing
constructor and `toString()` format are unchanged.

On macOS, no-update diagnostics still go to `onUpdaterUpdateNotAvailable`, but
no longer trigger `onUpdaterError`. Initialization errors are returned by
`setFeedURL` as a `PlatformException`, with the native code and error details.

Completion means Sparkle finished its update cycle, or WinSparkle reported no
update, failure, cancellation, or installer launch. It does not confirm a
successful installation. An available update can leave the native dialog open,
and events during app exit are best-effort. Cancellation is reported when the
native SDK exposes it; it is not inferred from every dialog closing.

These events require the updated native packages as well as the Dart package.
The existing `setFeedURL` API is unchanged; this adds no download transport hook.

## Related Links

- https://sparkle-project.org/
- https://winsparkle.org/

## License

[MIT](./LICENSE)
