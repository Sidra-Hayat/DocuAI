import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const failure = StorageFailure('Disk is full.');

  test('exposes the value or the failure, never both', () {
    const success = Success<int>(7);
    const failed = Failed<int>(failure);

    expect(success.isSuccess, isTrue);
    expect(success.valueOrNull, 7);
    expect(success.failureOrNull, isNull);

    expect(failed.isFailure, isTrue);
    expect(failed.valueOrNull, isNull);
    expect(failed.failureOrNull, failure);
  });

  test('fold collapses both branches', () {
    String describe(Result<int> result) => result.fold(
      onSuccess: (value) => 'got $value',
      onFailure: (failure) => failure.message,
    );

    expect(describe(const Success<int>(7)), 'got 7');
    expect(describe(const Failed<int>(failure)), 'Disk is full.');
  });

  test('map transforms a success and passes a failure through', () {
    expect(const Success<int>(7).map((value) => value * 2), const Success(14));
    expect(
      const Failed<int>(failure).map((value) => value * 2),
      const Failed<int>(failure),
    );
  });

  test('flatMap short-circuits on the first failure', () async {
    var ran = false;
    final result = await const Failed<int>(failure).flatMap<String>((value) async {
      ran = true;
      return const Success('unreachable');
    });

    expect(ran, isFalse);
    expect(result, const Failed<String>(failure));
  });

  test('flatMap chains a second fallible step on success', () async {
    final result = await const Success<int>(7).flatMap<String>(
      (value) async => Success('value is $value'),
    );

    expect(result, const Success('value is 7'));
  });

  test('equality is by value, so results can be compared in tests', () {
    expect(const Success<int>(7), const Success<int>(7));
    expect(const Success<int>(7), isNot(const Success<int>(8)));
    expect(const Failed<int>(failure), const Failed<int>(failure));
  });
}
