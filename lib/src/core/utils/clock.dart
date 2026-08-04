/// Source of the current time.
///
/// Use cases that stamp `updatedAt` take a [Clock] instead of calling
/// `DateTime.now()` directly, so a test can pin time to a fixed instant and
/// assert on the exact value rather than on a tolerance window.
typedef Clock = DateTime Function();

/// The production clock. Passed as the default argument everywhere a [Clock] is
/// required, so callers only supply one in tests.
DateTime systemClock() => DateTime.now();
