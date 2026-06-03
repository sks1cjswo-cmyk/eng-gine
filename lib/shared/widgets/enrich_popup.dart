import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/card/data/card_repository.dart';

/// Modal dialog for previewing enrich results before saving a card.
///
/// Usage:
/// ```dart
/// showDialog(
///   context: context,
///   builder: (_) => EnrichPopup(
///     selectedText: text,
///     contextSnippet: context,
///     sessionId: id,
///     cardType: 'word',
///   ),
/// );
/// ```
class EnrichPopup extends ConsumerStatefulWidget {
  const EnrichPopup({
    super.key,
    required this.selectedText,
    required this.contextSnippet,
    required this.sessionId,
    required this.cardType,
  });

  final String selectedText;
  final String contextSnippet;
  final String sessionId;
  final String cardType;

  @override
  ConsumerState<EnrichPopup> createState() => _EnrichPopupState();
}

class _EnrichPopupState extends ConsumerState<EnrichPopup> {
  late Future<EnrichCoreResult> _enrichFuture;

  @override
  void initState() {
    super.initState();
    _enrichFuture = ref.read(enrichServiceProvider).enrichCore(
          text: widget.selectedText,
          contextSnippet: widget.contextSnippet,
          cardType: widget.cardType,
        );
  }

  Future<void> _save(EnrichCoreResult result) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final service = ref.read(cardServiceProvider);
    final outcome = await service.saveManual(
      userId: userId,
      sessionId: widget.sessionId,
      sourceType: 'chat',
      text: widget.selectedText,
      contextSnippet: widget.contextSnippet,
      cardType: widget.cardType,
    );

    if (!mounted) return;
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome.reinforced
              ? 'Already saved — review priority boosted!'
              : 'Card saved!',
        ),
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: FutureBuilder<EnrichCoreResult>(
          future: _enrichFuture,
          builder: (context, snapshot) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Save as card',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _buildContent(context, snapshot),
                  ),
                ),

                // Footer actions
                if (snapshot.hasData)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: () => _save(snapshot.data!),
                          icon: const Icon(Icons.bookmark_add),
                          label: const Text('Save Card'),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AsyncSnapshot<EnrichCoreResult> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (snapshot.hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text('Failed to load: ${snapshot.error}'),
          ],
        ),
      );
    }

    final result = snapshot.data!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Original
        _Label('Original'),
        const SizedBox(height: 4),
        Text(
          result.originalText,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
        ),
        const SizedBox(height: 16),

        // Correction
        if (result.correctedText != null) ...[
          _Label('Correction'),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withAlpha(128),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              result.correctedText!,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Nuance
        _Label('Nuance'),
        const SizedBox(height: 4),
        Text(result.nuanceExplanation),
        const SizedBox(height: 16),

        // Examples
        if (result.alternativeExamples.isNotEmpty) ...[
          _Label('Examples'),
          const SizedBox(height: 4),
          ...result.alternativeExamples.map(
            (ex) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(child: Text(ex)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Full enrich loading notice
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .secondaryContainer
                .withAlpha(76),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                'Synonyms, confusables & more loading in background…',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
    );
  }
}
