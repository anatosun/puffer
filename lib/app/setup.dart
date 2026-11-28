import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'playback_providers.dart';
import 'providers.dart';

/// The first setup offered its options, which the person set or left as they were, so the step does not come again.
final setupPreferencesOfferedProvider =
    NotifierProvider<BoolSettingNotifier, bool>(
      () => BoolSettingNotifier('setup.preferencesOffered', false),
    );

/// Where the first setup goes after the Subsonic sign-in, or after the step it is on: Music Assistant, unless it was offered or is signed in; then the options; then home. Each step is offered once.
String nextSetupPage(T Function<T>(ProviderListenable<T> provider) read) {
  if (!read(maSetupOfferedProvider) && read(maCredentialsProvider) == null) {
    return '/setup/music-assistant';
  }
  if (!read(setupPreferencesOfferedProvider)) return '/setup/preferences';
  return '/home';
}
