import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/place_status.dart';
import '../services/auth_service.dart';
import '../services/import_service.dart';
import '../theme/app_spacing.dart';

/// Sign-in and saved-places import.
///
/// Deliberately blunt about the two constraints that shape this feature:
/// markers cannot be written back to Google Maps, and the API can only supply
/// Starred places. Hiding either would make the app look broken.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _busy = false;
  double? _uploadProgress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved places')),
      body: AnimatedBuilder(
        animation: AuthService.instance,
        builder: (context, _) {
          final auth = AuthService.instance;

          if (!auth.isAvailable) {
            return const _Message(
              icon: Icons.cloud_off_rounded,
              title: 'Sign-in is not configured',
              body: 'This build has no Firebase project or Google OAuth client '
                  'id, so signing in is switched off. FoodieRank works '
                  'normally without it.',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              AppSpacing.xxl,
            ),
            children: [
              _buildAccountTile(auth),
              if (auth.isSignedIn) ...[
                _buildLegend(),
                _buildTakeoutCard(),
                _buildDriveCard(auth),
                _buildApiCard(auth),
                _buildJobList(),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildAccountTile(AuthService auth) {
    if (!auth.isSignedIn) {
      return _Section(
        title: 'Show your Google Maps saves',
        children: [
          const Text(
            'Sign in to see which ranked places you have hearted, starred '
            'or flagged in Google Maps. Signing in is optional — every '
            'other feature works without it.',
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _busy ? null : _signIn,
            icon: const Icon(Icons.login_rounded, size: 18),
            label: const Text('Sign in with Google'),
          ),
        ],
      );
    }

    return _Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        leading: CircleAvatar(
          backgroundImage:
              auth.photoUrl != null ? NetworkImage(auth.photoUrl!) : null,
          child: auth.photoUrl == null ? const Icon(Icons.person) : null,
        ),
        title: Text(
          auth.displayName ?? auth.email ?? 'Signed in',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: auth.displayName != null ? Text(auth.email ?? '') : null,
        trailing: TextButton(
          onPressed: _busy ? null : _signOut,
          child: const Text('Sign out'),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    final theme = Theme.of(context);

    return _Section(
      title: 'What the icons mean',
      children: [
        for (final status in PlaceStatus.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Icon(status.icon,
                    color: status.colorFor(theme.brightness), size: 20),
                const SizedBox(width: AppSpacing.md),
                Text(status.label, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        Row(
          children: [
            Icon(Icons.bookmark,
                color: theme.colorScheme.onSurfaceVariant, size: 20),
            const SizedBox(width: AppSpacing.md),
            Text('In one of your lists', style: theme.textTheme.bodyMedium),
          ],
        ),
        const Divider(height: AppSpacing.xxl),
        Text(
          'Only one icon shows per place: heart, then star, then flag. '
          'Tap it to remove that mark and reveal the next one.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Removing a mark changes it in FoodieRank only. Google provides '
          'no way for apps to edit your saved places, so it will still be '
          'there in Google Maps.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildTakeoutCard() {
    final theme = Theme.of(context);

    return _Section(
      title: 'Import from Google Takeout',
      children: [
        Text(
          'The only way to get Loved, Want to go and your custom lists — '
          'Google offers no API for them.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'At takeout.google.com, export "Maps (your places)", then upload '
          'the .zip here.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_uploadProgress != null) ...[
          ClipRRect(
            borderRadius: AppRadius.pillAll,
            child: LinearProgressIndicator(
              value: _uploadProgress,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Uploading… ${((_uploadProgress ?? 0) * 100).round()}%',
              style: theme.textTheme.bodySmall),
        ] else
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _uploadTakeout,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Upload Takeout .zip'),
          ),
      ],
    );
  }

  /// Optional automation: Takeout can deliver to Drive on a schedule, and the
  /// backend picks the archives up. Kept visually secondary to the manual
  /// upload because it costs a broad permission.
  Widget _buildDriveCard(AuthService auth) {
    final theme = Theme.of(context);

    return _Section(
      title: 'Or let it update itself',
      children: [
        Text(
          'Takeout can email you a new export every 2 months and drop it '
          'straight into Drive. Connect Drive and FoodieRank will pick '
          'those up on its own — no uploading.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        // Be explicit about the cost. Google's own consent screen says
        // "See and download all your Google Drive files", and a user who
        // is surprised by that has been misled by us, not by Google.
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.tertiaryContainer,
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'This asks for read access to your whole Google Drive. Google '
                  'offers no narrower permission for files it created. Skip it '
                  'and uploading the .zip yourself works exactly as well.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (!auth.hasDriveGrant)
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _connectDrive,
            icon: const Icon(Icons.cloud_sync_rounded, size: 18),
            label: const Text('Connect Drive'),
          )
        else ...[
          Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Drive connected — checked twice a day.',
                    style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : _openTakeoutSchedule,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Set up the Takeout schedule'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'In Takeout: pick "Maps (your places)", set delivery to "Add to '
            'Drive", and choose every 2 months. Google gives no API for '
            'this, and the schedule runs for a year before it needs '
            'renewing.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildApiCard(AuthService auth) {
    final theme = Theme.of(context);

    return _Section(
      title: 'Sync Starred places automatically',
      children: [
        Text(
          'Google can send us your Starred places directly. It covers only '
          'stars, and an export can take anywhere from minutes to a couple '
          'of days.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (!auth.hasStarredPlacesGrant)
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _connect,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Connect'),
              )
            else ...[
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _startStarredImport,
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: const Text('Sync now'),
              ),
              TextButton(
                onPressed: _busy ? null : _resetAuthorization,
                child: const Text('Reset authorization'),
              ),
            ],
          ],
        ),
        if (auth.hasStarredPlacesGrant) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Google will not export the same data twice without an '
            'authorization reset, which it also does automatically 14 days '
            'after the first sync.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildJobList() {
    return StreamBuilder<List<ImportJob>>(
      stream: ImportService.instance.watchJobs(),
      builder: (context, snapshot) {
        final jobs = snapshot.data ?? const <ImportJob>[];
        if (jobs.isEmpty) return const SizedBox.shrink();

        return _Section(
          title: 'Recent imports',
          children: [for (final job in jobs) _buildJobRow(job)],
        );
      },
    );
  }

  Widget _buildJobRow(ImportJob job) {
    final theme = Theme.of(context);
    final label = job.source == ImportSource.takeout
        ? 'Takeout upload'
        : 'Starred places';

    final (IconData icon, Color color, String status) = switch (job.state) {
      ImportState.complete => (
          Icons.check_circle_rounded,
          theme.colorScheme.primary,
          '${job.placesImported ?? 0} places'
        ),
      ImportState.failed => (
          Icons.error_rounded,
          theme.colorScheme.error,
          job.error ?? 'Failed'
        ),
      ImportState.cancelled => (
          Icons.cancel_rounded,
          theme.colorScheme.outline,
          'Cancelled'
        ),
      _ => (
          Icons.hourglass_top_rounded,
          theme.colorScheme.tertiary,
          'In progress…'
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(
                  status,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    final ok = await AuthService.instance.signIn();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _toast('Sign-in was not completed.');
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await AuthService.instance.signOut();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _connectDrive() async {
    setState(() => _busy = true);
    final error = await AuthService.instance.connectGoogleDrive();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(error ??
        'Drive connected. Set up the Takeout schedule and imports will run '
        'on their own.');
  }

  /// Hand off to Takeout in the system browser, where the user is already
  /// signed in. There is no API to create the schedule and no URL parameter to
  /// preselect a product, so this is as far as automation can go.
  Future<void> _openTakeoutSchedule() async {
    final uri = Uri.parse('https://takeout.google.com/');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('Could not open Takeout. Visit takeout.google.com.');
    }
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    final error = await AuthService.instance.connectGoogleMapsData();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(error ?? 'Connected. You can sync your Starred places now.');
  }

  Future<void> _startStarredImport() async {
    setState(() => _busy = true);
    final error = await ImportService.instance.startStarredPlacesImport();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(error ??
        'Sync started. Google may take hours to prepare it — your places will '
        'appear once it lands.');
  }

  Future<void> _resetAuthorization() async {
    setState(() => _busy = true);
    final error = await ImportService.instance.resetAuthorization();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(error ?? 'Authorization reset. Connect again to sync.');
  }

  Future<void> _uploadTakeout() async {
    setState(() {
      _busy = true;
      _uploadProgress = 0;
    });

    final result = await ImportService.instance.uploadTakeoutArchive(
      onProgress: (p) {
        if (mounted) setState(() => _uploadProgress = p);
      },
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _uploadProgress = null;
    });

    if (result.cancelled) return;
    _toast(result.error ??
        'Uploaded. Your saved places will appear here shortly.');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }
}

/// The one card shape this screen uses. There were nine variations on
/// `Card` → `Padding(16)` → bold `Text` before, each with its own spacing.
class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        // Colour comes from the shared CardTheme, which knows which direction
        // "raised" runs in for the current scheme.
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: child,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Message({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
