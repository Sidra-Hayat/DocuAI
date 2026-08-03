import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/phase_placeholder.dart';

/// Full-text search across every document's OCR output.
///
/// Phase 6 replaces the placeholder with results from the inverted index.
class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: const PhasePlaceholder(
        icon: Icons.manage_search_outlined,
        title: 'Search your documents',
        description:
            'Find any document by the text inside it — searched locally, with '
            'no internet connection.',
        phase: 'Phase 6',
      ),
    );
  }
}
