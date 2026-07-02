import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:go_router/go_router.dart';

import '../core/constants/branding.dart';
import '../services/poll_service.dart';

/// Resolves a public share link (`/p/:shareSlug`) to a poll and opens it in
/// the full app shell — the entry point for links shared via
/// [ShareablePollResultCard]/[PollCard]'s share action.
///
/// Bots/crawlers requesting this path receive an Open Graph preview from the
/// `share-poll` Edge Function instead; this screen only ever runs for real
/// browsers that the function redirects here.
class PublicPollScreen extends StatefulWidget {
  const PublicPollScreen({super.key, required this.shareSlug});

  final String shareSlug;

  @override
  State<PublicPollScreen> createState() => _PublicPollScreenState();
}

class _PublicPollScreenState extends State<PublicPollScreen> {
  final PollService _pollService = PollService();

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final slug = widget.shareSlug.trim();
    if (slug.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This link is missing a poll.';
      });
      return;
    }

    try {
      final raw = await _pollService.getPollByShareSlug(slug);
      if (raw == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'This poll could not be found. It may have been deleted.';
        });
        return;
      }

      final poll = raw is Map<String, dynamic>
          ? raw
          : Map<String, dynamic>.from(raw as Map);
      final pollId = poll['id']?.toString();
      if (pollId == null || pollId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'This poll could not be found. It may have been deleted.';
        });
        return;
      }

      if (!mounted) return;
      context.go('/home/poll/$pollId');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message.isNotEmpty ? e.message : 'Could not load this poll.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not load this poll. Check your connection and try again.';
      });
    }
  }

  void _openApp() => context.go('/home');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _loading
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Opening poll…'),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 48,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error ?? 'Could not load this poll.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _openApp,
                        child: Text('Go to ${Branding.appName}'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
