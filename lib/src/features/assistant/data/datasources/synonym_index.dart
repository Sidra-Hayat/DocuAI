/// Offline synonym expansion for document vocabulary.
///
/// A curated list, not a thesaurus. A general-purpose one is both too large to
/// bundle and actively harmful here: expanding "bank" to "shore" would surface
/// the wrong page confidently. These groups cover the way the same thing gets
/// named differently across a bill, a contract and a receipt — the actual
/// reason a sensible question misses the page that answers it.
///
/// Everything is bidirectional: any member expands to every other member.
abstract final class SynonymIndex {
  /// Weight applied to a term matched through a synonym rather than exactly.
  ///
  /// Below 1 on purpose. A passage containing the user's own word is better
  /// evidence than one containing a word the app decided was equivalent, and
  /// the ranking should prefer it when both exist.
  static const double weight = 0.6;

  static const List<Set<String>> groups = <Set<String>>[
    // What the document is
    {'bill', 'invoice', 'statement', 'receipt'},
    {'contract', 'agreement', 'lease', 'tenancy'},
    {'policy', 'cover', 'coverage', 'insurance'},
    {'prescription', 'medication', 'medicine'},
    {'passport', 'id', 'identification', 'identity'},
    {'licence', 'license', 'permit'},
    {'warranty', 'guarantee'},

    // Money
    {'amount', 'total', 'sum', 'balance', 'payable'},
    {'cost', 'price', 'charge', 'fee', 'rate'},
    {'paid', 'payment', 'settled'},
    {'refund', 'reimbursement', 'rebate'},
    {'deposit', 'bond', 'security'},
    {'discount', 'reduction'},
    {'tax', 'vat', 'gst'},

    // Time
    {'due', 'deadline', 'payable', 'owing'},
    {'expires', 'expiry', 'expiration', 'valid'},
    {'start', 'starts', 'commencement', 'begins'},
    {'end', 'ends', 'termination', 'expiry'},
    {'renewal', 'renew', 'renewed'},
    {'period', 'term', 'duration'},

    // People and places
    {'tenant', 'renter', 'lessee', 'occupant'},
    {'landlord', 'lessor', 'owner'},
    {'customer', 'client', 'account', 'holder'},
    {'supplier', 'provider', 'vendor', 'company'},
    {'address', 'location', 'premises', 'property'},
    {'phone', 'telephone', 'mobile', 'contact'},
    {'email', 'mail'},

    // Reference numbers
    {'number', 'no', 'reference', 'ref', 'code'},
    {'account', 'acct'},

    // Utilities, since those are the bills people actually scan
    {'electricity', 'electric', 'power', 'energy'},
    {'water', 'sewerage'},
    {'gas', 'heating'},
    {'internet', 'broadband', 'wifi'},
    {'rent', 'rental'},
  ];

  /// Term to every other term sharing a group with it.
  ///
  /// Built once at first use rather than per query — a query with five terms
  /// would otherwise walk all of [groups] five times on every keystroke of a
  /// re-ask.
  static final Map<String, Set<String>> _lookup = _build();

  static Map<String, Set<String>> _build() {
    final lookup = <String, Set<String>>{};

    for (final group in groups) {
      for (final term in group) {
        lookup
            .putIfAbsent(term, () => <String>{})
            .addAll(group.where((other) => other != term));
      }
    }

    return lookup;
  }

  /// Alternatives for [term], excluding the term itself. Empty when unknown.
  static Set<String> alternativesFor(String term) =>
      _lookup[term] ?? const <String>{};

  /// Every alternative for every term in [terms], with the originals removed
  /// so exact and synonym matching stay distinguishable downstream.
  static Set<String> expand(Iterable<String> terms) {
    final originals = terms.toSet();
    final expanded = <String>{};

    for (final term in originals) {
      expanded.addAll(alternativesFor(term));
    }

    return expanded..removeAll(originals);
  }
}
