import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/constants/branding.dart';
import '../services/poll_service.dart';
import '../widgets/poll_card.dart';
import '../widgets/poll_result_chart.dart';

/// Builds the public embed URL for [shareSlug]
/// (`$publicShareBaseUrl/embed/poll/:shareSlug`), suitable for an
/// `<iframe src="...">`. Exposed for testing.
String embedUrlForShareSlug(String shareSlug) {
  return '${AppConfig.publicShareBaseUrl}/embed/poll/$shareSlug';
}

/// Builds a copy-pasteable `<iframe>` snippet embedding the poll at
/// [shareSlug]. Exposed for testing.
String embedSnippetForShareSlug(String shareSlug) {
  final url = embedUrlForShareSlug(shareSlug);
  return '<iframe src="$url" width="420" height="540" '
      'style="border:1px solid #eff3f4;border-radius:16px;" '
      'loading="lazy" title="${Branding.appName} poll"></iframe>';
}

/// Chrome-less poll view designed to be loaded inside a third-party site's
/// `<iframe>` via `/embed/poll/:shareSlug`. Shows just the poll card, its
/// results chart, and a small "Powered by [Branding.appName]" footer — no
/// app bar, bottom navigation, or other app chrome.
class EmbedPollScreen extends StatefulWidget {
  const EmbedPollScreen({super.key, required this.shareSlug});

  final String shareSlug;

  @override
  State<EmbedPollScreen> createState() => _EmbedPollScreenState();
}

class _EmbedPollScreenState extends State<EmbedPollScreen> {
  final PollService _pollService = PollService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final slug = widget.shareSlug.trim();
    if (slug.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This embed link is missing a poll.';
      });
      return;
    }

    try {
      final raw = await _pollService.getPollByShareSlug(slug);
      if (!mounted) return;
      if (raw == null) {
        setState(() {
          _loading = false;
          _error = 'This poll could not be found.';
        });
        return;
      }
      final poll = raw is Map<String, dynamic>
          ? raw
          : Map<String, dynamic>.from(raw as Map);
      setState(() {
        _loading = false;
        _poll = poll;
      });
      // EmbedPollScreen never routes through PollDetailScreen, so it needs
      // its own view-recording call - this is exactly the "external visitor"
      // case the views_count metric is meant to capture.
      final pollId = poll['id']?.toString();
      if (pollId != null && pollId.isNotEmpty) {
        _pollService.recordView(pollId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this poll.';
      });
    }
  }

  bool get _allowsEmbedding => _poll?['allow_embedding'] != false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = _EmbedMessage(icon: Icons.error_outline_rounded, message: _error!);
    } else if (!_allowsEmbedding) {
      body = const _EmbedMessage(
        icon: Icons.lock_outline_rounded,
        message: 'The poll author has turned off embedding for this poll.',
      );
    } else {
      final poll = _poll!;
      body = ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          PollCard(poll: poll, showTrendingScore: false),
          PollResultChart(poll: poll),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.how_to_vote_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Powered by ${Branding.appName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(child: body),
    );
  }
}

class _EmbedMessage extends StatelessWidget {
  const _EmbedMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
