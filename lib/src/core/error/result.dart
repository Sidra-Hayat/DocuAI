import 'failure.dart';

/// The return type of every repository method and use case.
///
/// Repositories never throw across the domain boundary — they return a
/// [Success] or a [Failed] carrying a [Failure]. Because [Result] is sealed,
/// the analyzer forces callers to handle both cases:
///
/// ```dart
/// final label = switch (await getDocument(id)) {
///   Success(:final value) => value.title,
///   Failed(:final failure) => failure.message,
/// };
/// ```
///
/// This is preferred over `dartz`'s `Either` for the same reason the project
/// avoids most dependencies: pattern matching on a sealed class is a language
/// feature, reads without a functional-programming vocabulary, and needs no
/// package to stay maintained.
sealed class Result<T> {
  const Result();

  /// Wraps a value that was produced successfully.
  const factory Result.success(T value) = Success<T>;

  /// Wraps a [Failure] describing why the operation did not complete.
  const factory Result.failed(Failure failure) = Failed<T>;

  bool get isSuccess => this is Success<T>;

  bool get isFailure => this is Failed<T>;

  /// The value, or `null` when this is a [Failed]. Prefer an exhaustive
  /// `switch` where the failure matters; this is for the cases where a missing
  /// value is genuinely equivalent to no value.
  T? get valueOrNull => switch (this) {
    Success(:final value) => value,
    Failed() => null,
  };

  Failure? get failureOrNull => switch (this) {
    Success() => null,
    Failed(:final failure) => failure,
  };

  /// Collapses both branches into a single value — the usual way a widget turns
  /// a result into something renderable.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Failure failure) onFailure,
  }) => switch (this) {
    Success(:final value) => onSuccess(value),
    Failed(:final failure) => onFailure(failure),
  };

  /// Transforms a successful value and passes any failure through untouched.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Success(:final value) => Success<R>(transform(value)),
    Failed(:final failure) => Failed<R>(failure),
  };

  /// Chains another fallible step, short-circuiting on the first failure.
  /// Used by use cases that call several repositories in sequence.
  Future<Result<R>> flatMap<R>(
    Future<Result<R>> Function(T value) transform,
  ) async => switch (this) {
    Success(:final value) => await transform(value),
    Failed(:final failure) => Failed<R>(failure),
  };
}

final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Success<T> &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => 'Success($value)';
}

final class Failed<T> extends Result<T> {
  const Failed(this.failure);

  final Failure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failed<T> &&
          runtimeType == other.runtimeType &&
          failure == other.failure;

  @override
  int get hashCode => Object.hash(runtimeType, failure);

  @override
  String toString() => 'Failed($failure)';
}

/// Every asynchronous repository and use case signature uses this alias, so the
/// intent reads at a glance: `FutureResult<Document>` rather than
/// `Future<Result<Document>>`.
typedef FutureResult<T> = Future<Result<T>>;
