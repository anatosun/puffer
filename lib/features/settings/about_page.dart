import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/messages.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/backdrop.dart';
import '../../ui/widgets/brand_mark.dart';

/// The project on GitHub, where the source, the releases and the issue tracker live.
const repositoryUrl = 'https://github.com/anatosun/puffer';

/// The version of the app as installed.
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// The version as the About page and bug reports show it: `0.1.0-alpha.18 (18)`.
String versionLabel(PackageInfo info) => info.buildNumber.isEmpty
    ? info.version
    : '${info.version} (${info.buildNumber})';

Future<void> _open(String url) async {
  final opened = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!opened) showMessage('No app could open $url');
}

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(packageInfoProvider).value;
    final version = info == null ? null : versionLabel(info);
    Widget link(IconData icon, String title, String url, {String? subtitle}) =>
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(
            subtitle ?? url.replaceFirst('https://', ''),
            style: TextStyle(color: context.muted),
          ),
          trailing: Icon(Icons.open_in_new, size: 18, color: context.faint),
          onTap: () => _open(url),
        );

    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('About')),
        body: ListView(
          children: [
            const SizedBox(height: 16),
            const Center(child: BrandMark(size: 120)),
            // The wordmark: lowercase, Inter Tight SemiBold, tight letter-spacing.
            Center(
              child: Text(
                'puffer',
                style: TextStyle(
                  fontFamily: 'InterTight',
                  fontWeight: FontWeight.w600,
                  fontSize: 34,
                  letterSpacing: -0.045 * 34,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Music from your Subsonic server',
                style: TextStyle(color: context.muted),
              ),
            ),
            const SizedBox(height: 16),
            // A tap copies the version, for bug reports.
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Version'),
              subtitle: Text(
                version ?? '…',
                style: TextStyle(color: context.muted),
              ),
              trailing: Icon(Icons.copy, size: 18, color: context.faint),
              onTap: version == null
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: 'Puffer $version'),
                      );
                      showMessage('Version copied');
                    },
            ),
            link(Icons.code, 'Source code', repositoryUrl),
            link(
              Icons.new_releases_outlined,
              'Releases and changes',
              '$repositoryUrl/releases',
            ),
            link(
              Icons.bug_report_outlined,
              'Report a problem',
              '$repositoryUrl/issues',
              subtitle:
                  'Issues on GitHub; copy the version above into your report',
            ),
            link(
              Icons.gavel_outlined,
              'Licence',
              '$repositoryUrl/blob/main/LICENSE',
              subtitle: 'GNU General Public License, version 3',
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Open-source licences'),
              subtitle: Text(
                'The libraries Puffer is built with',
                style: TextStyle(color: context.muted),
              ),
              trailing: Icon(Icons.chevron_right, color: context.faint),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Puffer',
                applicationVersion: version,
                applicationIcon: const BrandMark(size: 64),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
