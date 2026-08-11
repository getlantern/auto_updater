import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundles the expected EdDSA-capable WinSparkle distribution', () {
    const distribution = 'windows/WinSparkle-0.9.4';
    final versionHeader = File('$distribution/include/winsparkle-version.h');
    final apiHeader = File('$distribution/include/winsparkle.h');

    expect(versionHeader.existsSync(), isTrue);
    expect(apiHeader.existsSync(), isTrue);
    expect(
      versionHeader.readAsStringSync(),
      allOf(
        contains('#define WIN_SPARKLE_VERSION_MAJOR   0'),
        contains('#define WIN_SPARKLE_VERSION_MINOR   9'),
        contains('#define WIN_SPARKLE_VERSION_MICRO   4'),
      ),
    );
    expect(
      apiHeader.readAsStringSync(),
      contains('win_sparkle_set_eddsa_public_key'),
    );

    for (final artifact in <String>[
      '$distribution/x64/Release/WinSparkle.dll',
      '$distribution/x64/Release/WinSparkle.lib',
      '$distribution/bin/winsparkle-tool.exe',
    ]) {
      expect(File(artifact).existsSync(), isTrue, reason: 'missing $artifact');
    }
  });
}
