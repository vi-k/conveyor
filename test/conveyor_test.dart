import 'dart:async';

import 'package:conveyor/conveyor.dart';
import 'package:test/test.dart';

import 'helpers/conveyor.dart';
import 'helpers/result.dart';
import 'helpers/state.dart';

void main() {
  group('check state.', () {
    late TestConveyor conveyor;
    late List<(MyState, MyState)> states;
    late List<(String, ConveyorResult)> results;

    void addEvents() {
      conveyor
        ..init().saveToResults('init', results)
        ..incrementA().saveToResults('incrementA', results)
        ..incrementB().saveToResults('incrementB', results)
        ..finish().saveToResults('finish', results);
    }

    List<String> statesToStrings() => states
        .map((e) => '${e.$1}${e.$1 == e.$2 ? '' : ' vs ${e.$2}'}')
        .toList();

    List<String> resultsToStrings() =>
        results.map((e) => '${e.$1}: ${e.$2}').toList();

    Future<void> awaitResults() => results.map((e) => e.$2.future).wait;

    setUp(() {
      states = [];
      results = [];
      conveyor = TestConveyor(const Initial())
        ..stream.listen((state) {
          final realState = conveyor.state();
          print(
            '** state from stream: $state'
            '${realState == state ? '' : ', but real state: $realState'}',
          );
          states.add((state, realState));
        });
    });

    tearDown(() async {
      await conveyor.close();
    });

    test('Normal execution', () async {
      addEvents();

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
        '$Ready(a: 0, b: 0)',
        '$Ready(a: 1, b: 0)',
        '$Ready(a: 1, b: 1)',
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: completed',
        'incrementA: completed',
        'incrementB: completed',
        'finish: completed',
      ]);
    });

    test('Close immediately', () async {
      addEvents();

      unawaited(conveyor.close());

      await awaitResults();

      expect(statesToStrings(), <String>[]);

      expect(resultsToStrings(), [
        'init: $RemovedFromQueueManually()',
        'incrementA: $RemovedFromQueueManually()',
        'incrementB: $RemovedFromQueueManually()',
        'finish: $RemovedFromQueueManually()',
      ]);
    });

    test('Close by microtask', () async {
      addEvents();

      await Future.microtask(() {
        conveyor.close();
      });

      await awaitResults();

      expect(statesToStrings(), <String>[]);

      expect(resultsToStrings(), [
        'init: $CancelledManually()',
        'incrementA: $RemovedFromQueueManually()',
        'incrementB: $RemovedFromQueueManually()',
        'finish: $RemovedFromQueueManually()',
      ]);
    });

    test('Close after 50 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 50));
      unawaited(conveyor.close());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
      ]);

      expect(resultsToStrings(), [
        'init: $CancelledManually()',
        'incrementA: $RemovedFromQueueManually()',
        'incrementB: $RemovedFromQueueManually()',
        'finish: $RemovedFromQueueManually()',
      ]);
    });

    test('Close after 150 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 150));
      unawaited(conveyor.close());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
      ]);

      expect(resultsToStrings(), [
        'init: $CancelledManually()',
        'incrementA: $RemovedFromQueueManually()',
        'incrementB: $RemovedFromQueueManually()',
        'finish: $RemovedFromQueueManually()',
      ]);
    });

    test('Close after 250 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 250));
      unawaited(conveyor.close());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
      ]);

      expect(resultsToStrings(), [
        'init: $CancelledManually()',
        'incrementA: $RemovedFromQueueManually()',
        'incrementB: $RemovedFromQueueManually()',
        'finish: $RemovedFromQueueManually()',
      ]);
    });

    test('Close after 350 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 350));
      unawaited(conveyor.close());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
        '$Ready(a: 0, b: 0)',
      ]);

      expect(resultsToStrings(), [
        'init: completed',
        'incrementA: $CancelledManually()',
        'incrementB: $RemovedFromQueueManually()',
        'finish: $RemovedFromQueueManually()',
      ]);
    });

    test('Close after 450 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 450));
      unawaited(conveyor.close());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
        '$Ready(a: 0, b: 0)',
        '$Ready(a: 1, b: 0)',
      ]);

      expect(resultsToStrings(), [
        'init: completed',
        'incrementA: completed',
        'incrementB: $CancelledManually()',
        'finish: $RemovedFromQueueManually()',
      ]);
    });

    test('Close after 550 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 550));
      unawaited(conveyor.close());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
        '$Ready(a: 0, b: 0)',
        '$Ready(a: 1, b: 0)',
        '$Ready(a: 1, b: 1)',
      ]);

      expect(resultsToStrings(), [
        'init: completed',
        'incrementA: completed',
        'incrementB: completed',
        'finish: $CancelledManually()',
      ]);
    });

    test('Close after 650 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 650));
      unawaited(conveyor.close());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
        '$Ready(a: 0, b: 0)',
        '$Ready(a: 1, b: 0)',
        '$Ready(a: 1, b: 1)',
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: completed',
        'incrementA: completed',
        'incrementB: completed',
        'finish: completed',
      ]);
    });

    test('Change state immediately', () async {
      addEvents();

      conveyor.externalSetState(const Disposed());

      await awaitResults();

      expect(statesToStrings(), [
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: $RemovedFromQueueByEventContidion()',
        'incrementA: $RemovedFromQueueByEventContidion()',
        'incrementB: $RemovedFromQueueByEventContidion()',
        'finish: $RemovedFromQueueByEventContidion()',
      ]);
    });

    test('Change state by microtask', () async {
      addEvents();

      await Future.microtask(() {
        conveyor.externalSetState(const Disposed());
      });

      await awaitResults();

      expect(statesToStrings(), [
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: $CancelledByEventContidion()',
        'incrementA: $RemovedFromQueueByEventContidion()',
        'incrementB: $RemovedFromQueueByEventContidion()',
        'finish: $RemovedFromQueueByEventContidion()',
      ]);
    });

    test('Change state after 50 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 50));
      conveyor.externalSetState(const Disposed());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: $CancelledByEventContidion()',
        'incrementA: $RemovedFromQueueByEventContidion()',
        'incrementB: $RemovedFromQueueByEventContidion()',
        'finish: $RemovedFromQueueByEventContidion()',
      ]);
    });

    test('Change state after 150 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 150));
      conveyor.externalSetState(const Disposed());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: $CancelledByEventContidion()',
        'incrementA: $RemovedFromQueueByEventContidion()',
        'incrementB: $RemovedFromQueueByEventContidion()',
        'finish: $RemovedFromQueueByEventContidion()',
      ]);
    });

    test('Change state after 250 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 250));
      conveyor.externalSetState(const Disposed());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: $CancelledByEventContidion()',
        'incrementA: $RemovedFromQueueByEventContidion()',
        'incrementB: $RemovedFromQueueByEventContidion()',
        'finish: $RemovedFromQueueByEventContidion()',
      ]);
    });

    test('Change state after 350 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 350));
      conveyor.externalSetState(const Disposed());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
        '$Ready(a: 0, b: 0)',
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: completed',
        'incrementA: $CancelledByEventContidion()',
        'incrementB: $RemovedFromQueueByEventContidion()',
        'finish: $RemovedFromQueueByEventContidion()',
      ]);
    });

    test('Change state after 450 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 450));
      conveyor.externalSetState(const Disposed());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
        '$Ready(a: 0, b: 0)',
        '$Ready(a: 1, b: 0)',
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: completed',
        'incrementA: completed',
        'incrementB: $CancelledByEventContidion()',
        'finish: $RemovedFromQueueByEventContidion()',
      ]);
    });

    test('Change state after 550 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 550));
      conveyor.externalSetState(const Disposed());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
        '$Ready(a: 0, b: 0)',
        '$Ready(a: 1, b: 0)',
        '$Ready(a: 1, b: 1)',
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: completed',
        'incrementA: completed',
        'incrementB: completed',
        'finish: $CancelledByEventContidion()',
      ]);
    });

    test('Change state after 650 ms', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 650));
      conveyor.externalSetState(const Disposed());

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
        '$Ready(a: 0, b: 0)',
        '$Ready(a: 1, b: 0)',
        '$Ready(a: 1, b: 1)',
        '$Disposed()',
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: completed',
        'incrementA: completed',
        'incrementB: completed',
        'finish: completed',
      ]);
    });

    test('Change state during incrementA', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 350));
      conveyor.externalSetState(const Ready(a: 10, b: 10));

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
        '$Ready(a: 0, b: 0)',
        '$Ready(a: 10, b: 10)',
        '$Ready(a: 11, b: 10)',
        '$Ready(a: 11, b: 11)',
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: completed',
        'incrementA: completed',
        'incrementB: completed',
        'finish: completed',
      ]);
    });

    test('Change state during incrementB', () async {
      addEvents();

      await Future<void>.delayed(const Duration(milliseconds: 450));
      conveyor.externalSetState(const Ready(a: 10, b: 10));

      await awaitResults();

      expect(statesToStrings(), [
        '$InProgress(progress: 0)',
        '$InProgress(progress: 50)',
        '$InProgress(progress: 100)',
        '$Ready(a: 0, b: 0)',
        '$Ready(a: 1, b: 0)',
        '$Ready(a: 10, b: 10)',
        '$Ready(a: 10, b: 11)',
        '$Disposed()',
      ]);

      expect(resultsToStrings(), [
        'init: completed',
        'incrementA: completed',
        'incrementB: completed',
        'finish: completed',
      ]);
    });

    test('Extremal test', () async {
      conveyor.extremalTest().saveToResults('extremalTest', results);
      await awaitResults();

      await Future(() {});

      expect(statesToStrings(), [
        '$Ready(a: 0, b: 0)',
        '$Ready(a: 1, b: 1)',
        '$Ready(a: 2, b: 2)',
      ]);

      // expect(resultsToStrings(), [
      //   'init: completed',
      //   'incrementA: completed',
      //   'incrementB: completed',
      //   'finish: completed',
      // ]);
    });
  });
}
