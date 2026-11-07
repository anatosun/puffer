import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licences of the bundled fonts and icons to the licences page, next to those of the packages. Both fonts are under the SIL Open Font License 1.1, which asks that the licence ship with the font. The Music Assistant icon set is under Apache-2.0, with icons from Lucide under ISC, as its attribution file records.
void registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final (font, file) in const [
      ('Noto Sans', 'assets/fonts/NotoSans-LICENSE.txt'),
      ('Inter Tight', 'assets/fonts/InterTight-LICENSE.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString(file));
    }
    yield LicenseEntryWithLineBreaks([
      'Music Assistant shared icons',
    ], await rootBundle.loadString('assets/player_icons/LICENSE.txt'));
    yield LicenseEntryWithLineBreaks([
      'Music Assistant shared icons',
    ], await rootBundle.loadString('assets/player_icons/ATTRIBUTION.md'));
  });
}
