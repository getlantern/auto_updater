# auto_updater_windows

[![pub version][pub-image]][pub-url]

[pub-image]: https://img.shields.io/pub/v/auto_updater_windows.svg
[pub-url]: https://pub.dev/packages/auto_updater_windows

The Windows implementation of [auto_updater](https://pub.dev/packages/auto_updater).

## WinSparkle

This package bundles WinSparkle 0.9.4. Applications can configure an EdDSA
public key with WinSparkle's `EdDSAPub` resource and sign updates with the
bundled `windows/WinSparkle-0.9.4/bin/winsparkle-tool.exe`. The public Dart API
continues to be provided by `auto_updater`.

## License

[MIT](./LICENSE)
