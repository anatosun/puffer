import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licences of the bundled fonts to the licences page, next to those of the packages. Both fonts are under the SIL Open Font License 1.1, which asks that the licence ship with the font.
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
  });
}
