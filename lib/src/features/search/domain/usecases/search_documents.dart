import '../../../../core/error/result.dart';
import '../entities/search_hit.dart';
import '../repositories/search_repository.dart';

/// Runs a query against the index.
///
/// Holds the one rule the repository should not have to know about: a query
/// shorter than [minQueryLength] returns nothing at all. A single character
/// matches most of the library, so the results are useless and the work is
/// wasted — and this fires on every keystroke.
class SearchDocuments {
  const SearchDocuments(this._repository);

  final SearchRepository _repository;

  static const int minQueryLength = 2;

  AsyncResult<List<SearchHit>> call(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < minQueryLength) {
      return const Success(<SearchHit>[]);
    }
    return _repository.search(trimmed);
  }
}
