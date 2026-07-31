import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/place_status.dart';
import '../services/auth_service.dart';
import '../services/import_service.dart';

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
              icon: Icons.cloud_off,
              title: 'Sign-in is not configured',
              body: 'This build has no Firebase project or Google OAuth client '
                  'id, so signing in is switched off. FoodieRank works '
                  'normally without it.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildAccountTile(auth),
              const SizedBox(height: 16),
              if (auth.isSignedIn) ...[
                _buildLegend(),
                const SizedBox(height: 16),
                _buildTakeoutCard(),
                const SizedBox(height: 12),
                _buildDriveCard(auth),
                const SizedBox(height: 12),
                _buildApiCard(auth),
                const SizedBox(height: 16),
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
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Show your Google Maps saves',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to see which ranked places you have hearted, starred '
                'or flagged in Google Maps. Signing in is optional — every '
                'other feature works without it.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _signIn,
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              auth.photoUrl != null ? NetworkImage(auth.photoUrl!) : null,
          child: auth.photoUrl == null ? const Icon(Icons.person) : null,
        ),
        title: Text(auth.displayName ?? auth.email ?? 'Signed in'),
        subtitle: auth.displayName != null ? Text(auth.email ?? '') : null,
        trailing: TextButton(
          onPressed: _busy ? null : _signOut,
          child: const Text('Sign out'),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('What the icons mean',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            for (final status in PlaceStatus.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(status.icon, color: status.color, size: 20),
                    const SizedBox(width: 10),
                    Text(status.label),
                  ],
                ),
              ),
            Row(
              children: [
                Icon(Icons.bookmark, color: Colors.blueGrey[600], size: 20),
                const SizedBox(width: 10),
                const Text('In one of your lists'),
              ],
            ),
            const Divider(height: 24),
            const Text(
              'Only one icon shows per place: heart, then star, then flag. '
              'Tap it to remove that mark and reveal the next one.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              'Removing a mark changes it in FoodieRank only. Google provides '
              'no way for apps to edit your saved places, so it will still be '
              'there in Google Maps.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTakeoutCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Import from Google Takeout',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'The only way to get Loved, Want to go and your custom lists — '
              'Google offers no API for them.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'At takeout.google.com, export "Maps (your places)", then upload '
              'the .zip here.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (_uploadProgress != null) ...[
              LinearProgressIndicator(value: _uploadProgress),
              const SizedBox(height: 8),
              Text('Uploading… ${((_uploadProgress ?? 0) * 100).round()}%',
                  style: const TextStyle(fontSize: 12)),
            ] else
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _uploadTakeout,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload Takeout .zip'),
              ),
          ],
        ),
      ),
    );
  }

  /// Optional automation: Takeout can deliver to Drive on a schedule, and the
  /// backend picks the archives up. Kept visually secondary to the manual
  /// upload because it costs a broad permission.
  Widget _buildDriveCard(AuthService auth) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Or let it update itself',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Takeout can email you a new export every 2 months and drop it '
              'straight into Drive. Connect Drive and FoodieRank will pick '
              'those up on its own — no uploading.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            // Be explicit about the cost. Google's own consent screen says
            // "See and download all your Google Drive files", and a user who
            // is surprised by that has been misled by us, not by Google.
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'This asks for read access to your whole Google Drive. Google '
                'offers no narrower permission for files it created. Skip it '
                'and uploading the .zip yourself works exactly as well.',
                style: TextStyle(fontSize: 11),
              ),
            ),
            const SizedBox(height: 12),
            if (!auth.hasDriveGrant)
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _connectDrive,
                icon: const Icon(Icons.cloud_sync),
                label: const Text('Connect Drive'),
              )
            else ...[
              Row(
                children: [
                  const Icon(Icons.check_circle, size: 18, color: Colors.green),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Drive connected — checked twice a day.',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _openTakeoutSchedule,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Set up the Takeout schedule'),
              ),
              const SizedBox(height: 6),
              const Text(
                'In Takeout: pick "Maps (your places)", set delivery to "Add to '
                'Drive", and choose every 2 months. Google gives no API for '
                'this, and the schedule runs for a year before it needs '
                'renewing.',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApiCard(AuthService auth) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sync Starred places automatically',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Google can send us your Starred places directly. It covers only '
              'stars, and an export can take anywhere from minutes to a couple '
              'of days.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!auth.hasStarredPlacesGrant)
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _connect,
                    icon: const Icon(Icons.link),
                    label: const Text('Connect'),
                  )
                else ...[
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _startStarredImport,
                    icon: const Icon(Icons.sync),
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
              const SizedBox(height: 8),
              const Text(
                'Google will not export the same data twice without an '
                'authorization reset, which it also does automatically 14 days '
                'after the first sync.',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildJobList() {
    return StreamBuilder<List<ImportJob>>(
      stream: ImportService.instance.watchJobs(),
      builder: (context, snapshot) {
        final jobs = snapshot.data ?? const <ImportJob>[];
        if (jobs.isEmpty) return const SizedBox.shrink();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recent imports',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final job in jobs) _buildJobRow(job),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildJobRow(ImportJob job) {
    final label = job.source == ImportSource.takeout
        ? 'Takeout upload'
        : 'Starred places';

    final (IconData icon, Color color, String status) = switch (job.state) {
      ImportState.complete => (
          Icons.check_circle,
          Colors.green,
          '${job.placesImported ?? 0} places'
        ),
      ImportState.failed => (Icons.error, Colors.red, job.error ?? 'Failed'),
      ImportState.cancelled => (Icons.cancel, Colors.grey, 'Cancelled'),
      _ => (Icons.hourglass_top, Colors.orange, 'In progress…'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                Text(
                  status,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
