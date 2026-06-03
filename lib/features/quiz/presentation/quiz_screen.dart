import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/quiz_provider.dart';
import '../domain/quiz_card_model.dart';
import '../domain/sm2_algorithm.dart';

class QuizScreen extends ConsumerWidget {
  const QuizScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(quizSessionProvider);
    final dueCardsAsync = ref.watch(quizDueCardsProvider);

    // If no active session, show the start screen
    if (session == null) {
      return _QuizStartScreen(dueCardsAsync: dueCardsAsync);
    }

    // Session done
    if (session.isDone) {
      return _QuizResultScreen(gradedCount: session.gradedCount);
    }

    // Active quiz
    return _QuizCardScreen(session: session);
  }
}

// ---------------------------------------------------------------------------
// Start screen
// ---------------------------------------------------------------------------

class _QuizStartScreen extends ConsumerWidget {
  const _QuizStartScreen({required this.dueCardsAsync});
  final AsyncValue<List<QuizCard>> dueCardsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz')),
      body: Center(
        child: dueCardsAsync.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
          data: (cards) => _StartContent(cards: cards),
        ),
      ),
    );
  }
}

class _StartContent extends ConsumerWidget {
  const _StartContent({required this.cards});
  final List<QuizCard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.quiz,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            cards.isEmpty
                ? 'All caught up!'
                : '${cards.length} card${cards.length == 1 ? '' : 's'} due',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            cards.isEmpty
                ? 'Come back later for your next review.'
                : 'Ready to review?',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withAlpha(153),
                ),
          ),
          const SizedBox(height: 32),
          if (cards.isNotEmpty)
            FilledButton.icon(
              onPressed: () {
                ref.read(quizSessionProvider.notifier).startSession(cards);
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Review'),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quiz card screen
// ---------------------------------------------------------------------------

class _QuizCardScreen extends ConsumerWidget {
  const _QuizCardScreen({required this.session});
  final QuizSessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = session.currentCard!;
    final total = session.cards.length;
    final current = session.currentIndex + 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('$current / $total'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            ref.read(quizSessionProvider.notifier).build();
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: current / total,
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700;
          return isWide
              ? _WideCardLayout(
                  card: card,
                  session: session,
                )
              : _NarrowCardLayout(
                  card: card,
                  session: session,
                );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wide layout (desktop/tablet) — side by side
// ---------------------------------------------------------------------------

class _WideCardLayout extends ConsumerWidget {
  const _WideCardLayout({required this.card, required this.session});
  final QuizCard card;
  final QuizSessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        // Front side
        Expanded(
          child: _CardFront(card: card),
        ),
        const VerticalDivider(width: 1),
        // Back side (always visible on wide)
        Expanded(
          child: _CardBack(
            card: card,
            isRevealed: session.isAnswerRevealed,
            onReveal: () =>
                ref.read(quizSessionProvider.notifier).revealAnswer(),
            onGrade: (q) =>
                ref.read(quizSessionProvider.notifier).gradeCard(q),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Narrow layout (mobile) — flip card
// ---------------------------------------------------------------------------

class _NarrowCardLayout extends ConsumerWidget {
  const _NarrowCardLayout({required this.card, required this.session});
  final QuizCard card;
  final QuizSessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: session.isAnswerRevealed
                ? _CardBack(
                    card: card,
                    isRevealed: true,
                    onReveal: () {},
                    onGrade: (q) =>
                        ref.read(quizSessionProvider.notifier).gradeCard(q),
                  )
                : _CardFront(card: card),
          ),
        ),
        if (!session.isAnswerRevealed)
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    ref.read(quizSessionProvider.notifier).revealAnswer(),
                child: const Text('Show Answer'),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Card front (question side)
// ---------------------------------------------------------------------------

class _CardFront extends StatelessWidget {
  const _CardFront({required this.card});
  final QuizCard card;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SourceChip(sourceType: card.sourceType),
              const SizedBox(width: 8),
              _CardTypeChip(cardType: card.cardType),
              if (card.reinforceCount > 0) ...[
                const SizedBox(width: 8),
                _ReinforceChip(count: card.reinforceCount),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Text(
            card.originalText,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
          ),
          if (card.contextSnippet != null &&
              card.contextSnippet != card.originalText) ...[
            const SizedBox(height: 16),
            Text(
              'Context:',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              card.contextSnippet!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(153),
                    fontStyle: FontStyle.italic,
                  ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card back (answer side)
// ---------------------------------------------------------------------------

class _CardBack extends StatelessWidget {
  const _CardBack({
    required this.card,
    required this.isRevealed,
    required this.onReveal,
    required this.onGrade,
  });

  final QuizCard card;
  final bool isRevealed;
  final VoidCallback onReveal;
  final ValueChanged<int> onGrade;

  @override
  Widget build(BuildContext context) {
    if (!isRevealed) {
      return Center(
        child: FilledButton(
          onPressed: onReveal,
          child: const Text('Show Answer'),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Correction
          if (card.correctedText != null) ...[
            _SectionLabel('Corrected'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withAlpha(128),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                card.correctedText!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Nuance explanation
          if (card.nuanceExplanation != null) ...[
            _SectionLabel('Nuance'),
            const SizedBox(height: 6),
            Text(card.nuanceExplanation!,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
          ],

          // Alternative examples
          if (card.alternativeExamples.isNotEmpty) ...[
            _SectionLabel('Examples'),
            const SizedBox(height: 6),
            ...card.alternativeExamples.map(
              (ex) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(ex,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Confusable with
          if (card.confusableWith.isNotEmpty) ...[
            _SectionLabel('Easy to confuse with'),
            const SizedBox(height: 6),
            ...card.confusableWith.map(
              (c) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c['expr'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (c['difference'] != null)
                        Text(
                          c['difference']!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Synonyms
          if (card.synonyms.isNotEmpty) ...[
            _SectionLabel('Similar expressions'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: card.synonyms
                  .map((s) => Chip(label: Text(s['expr'] ?? '')))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Homonyms
          if (card.homonyms.isNotEmpty) ...[
            _SectionLabel('Same sound, different meaning'),
            const SizedBox(height: 6),
            ...card.homonyms.map(
              (h) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      TextSpan(
                        text: '${h['word']}: ',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: h['meaning'] ?? ''),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Collocations
          if (card.collocations.isNotEmpty) ...[
            _SectionLabel('Common collocations'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: card.collocations
                  .map((c) => Chip(
                        label: Text(c),
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .secondaryContainer,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Enrich status indicator
          if (card.enrichStatus == 'core') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 6),
                Text(
                  'Loading more details…',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey,
                      ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 32),

          // Grade buttons
          _GradeButtons(onGrade: onGrade),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grade buttons (Again / Hard / Good / Easy)
// ---------------------------------------------------------------------------

class _GradeButtons extends StatelessWidget {
  const _GradeButtons({required this.onGrade});
  final ValueChanged<int> onGrade;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How well did you remember?',
          style: Theme.of(context).textTheme.labelMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _GradeButton(
              label: 'Again',
              sublabel: '<1d',
              color: Colors.red.shade600,
              onTap: () => onGrade(Sm2Algorithm.qualityAgain),
            ),
            const SizedBox(width: 8),
            _GradeButton(
              label: 'Hard',
              sublabel: '~1d',
              color: Colors.orange.shade600,
              onTap: () => onGrade(Sm2Algorithm.qualityHard),
            ),
            const SizedBox(width: 8),
            _GradeButton(
              label: 'Good',
              sublabel: '~6d',
              color: Colors.green.shade600,
              onTap: () => onGrade(Sm2Algorithm.qualityGood),
            ),
            const SizedBox(width: 8),
            _GradeButton(
              label: 'Easy',
              sublabel: '>6d',
              color: Colors.blue.shade600,
              onTap: () => onGrade(Sm2Algorithm.qualityEasy),
            ),
          ],
        ),
      ],
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            border: Border.all(color: color.withAlpha(76)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                sublabel,
                style: TextStyle(
                  color: color.withAlpha(178),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result screen
// ---------------------------------------------------------------------------

class _QuizResultScreen extends ConsumerWidget {
  const _QuizResultScreen({required this.gradedCount});
  final int gradedCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz Done')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Session complete!',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Reviewed $gradedCount card${gradedCount == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(153),
                    ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () {
                  // Reset session — will show StartScreen
                  ref.invalidate(quizSessionProvider);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Back to Quiz'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helper widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
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

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.sourceType});
  final String sourceType;

  @override
  Widget build(BuildContext context) {
    final label = switch (sourceType) {
      'chat' => 'Chat',
      'journal' => 'Journal',
      'youtube' => 'YouTube',
      _ => sourceType,
    };
    return Chip(label: Text(label, style: const TextStyle(fontSize: 11)));
  }
}

class _CardTypeChip extends StatelessWidget {
  const _CardTypeChip({required this.cardType});
  final String cardType;

  @override
  Widget build(BuildContext context) {
    final label = switch (cardType) {
      'word' => 'Word',
      'phrase' => 'Phrase',
      'sentence' => 'Sentence',
      _ => cardType,
    };
    return Chip(label: Text(label, style: const TextStyle(fontSize: 11)));
  }
}

class _ReinforceChip extends StatelessWidget {
  const _ReinforceChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: Colors.red.shade50,
      label: Text(
        'Repeated $count×',
        style: TextStyle(
          fontSize: 11,
          color: Colors.red.shade700,
        ),
      ),
    );
  }
}
