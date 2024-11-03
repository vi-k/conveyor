@Timeout(Duration(seconds: 5))
library;

import 'dart:async';

import 'package:conveyor/conveyor.dart';
import 'package:conveyor/src/debug_logger.dart';
import 'package:conveyor/utils.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conveyors/test_conveyor/event.dart';
import 'conveyors/test_conveyor/state.dart';
import 'conveyors/test_conveyor/test_conveyor.dart';
import 'utils/fake_async.dart';
import 'utils/result.dart';

void main() {
  debug = const PrintConveyorDebugLogger(prefix: '[Conveyor] * ');

  group('Conveyor.', () {
    late TestConveyor conveyor;
    late List<(TestState, TestState)> states;
    late List<(String, ConveyorResult)> results;

    List<String> resultsToStrings() =>
        results.map((e) => '${e.$1} ${e.$2}').toList();

    bool identicalResults(int index1, int index2) =>
        identical(results[index1].$2, results[index2].$2);

    Future<void> awaitResults() => results.map((e) => e.$2.future).wait;

    setUp(() async {
      states = [];
      results = [];
      conveyor = TestConveyor(const Initial())
        ..stream.listen((state) {
          final realState = conveyor.state;
          conveyor.log(
            'state: $state'
            '${realState == state ? '' : ', but real state: $realState'}',
          );
          states.add((state, realState));
        });
      await Future(() {});
    });

    tearDown(() => conveyor.close());

    group('State.', () {
      test(
        'Simple test',
        () => fakeAsync((async) {
          final event = TestEvent<TestState, TestState>(
            key: 'test',
            (state) async* {
              yield const Preparing();
              yield const Preparing(progress: 50);
              yield const Preparing(progress: 100);
              yield const Working();
              yield const Disposed();
            },
          );

          conveyor.queue.add(event).saveToResults(results);

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test] started',
            'state: $Preparing(progress: 0)',
            'state: $Preparing(progress: 50)',
            'state: $Preparing(progress: 100)',
            'state: $Working(a: 0, b: 0)',
            'state: $Disposed()',
            '[test] done',
          ]);

          expect(resultsToStrings(), [
            '[test] completed',
          ]);
        }),
      );

      group('Closing.', () {
        void addEvents() {
          final initEvent = TestEvent<Initial, TestState>(
            key: 'init',
            // checkStateBeforeProcessing: (state) => state is Initial,
            // Отменяем при любом внешнем изменении состояния.
            checkStateOnExternalChange: (state) => false,
            (state) async* {
              yield const Preparing();

              await Future<void>.delayed(const Duration(milliseconds: 100));

              yield state
                  .isA<Preparing>()
                  .test((it) => it.progress == 0)
                  .use((it) => it.copyWith(progress: 50));

              await Future<void>.delayed(const Duration(milliseconds: 100));

              yield state
                  .isA<Preparing>()
                  .test((it) => it.progress == 50)
                  .use((it) => it.copyWith(progress: 100));

              await Future<void>.delayed(const Duration(milliseconds: 100));

              yield state
                  .isA<Preparing>()
                  .test((it) => it.progress == 100)
                  .use((_) => const Working());
            },
          );
          final incrementAEvent = TestEvent<Working, Working>(
            key: 'incrementA',
            (state) async* {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              yield state.use((it) => it.copyWith(a: it.a + 1));
            },
          );
          final incrementBEvent = TestEvent<Working, Working>(
            key: 'incrementB',
            (state) async* {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              yield state.use((it) => it.copyWith(b: it.b + 1));
            },
          );
          final finishEvent = TestEvent<TestState, Disposed>(
            key: 'finish',
            checkStateBeforeProcessing: (state) => state is! Disposed,
            checkStateOnExternalChange: (state) => state is! Disposed,
            (state) async* {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              yield const Disposed();
            },
          );

          conveyor.queue
            ..add(initEvent).saveToResults(results)
            ..add(incrementAEvent).saveToResults(results)
            ..add(incrementBEvent).saveToResults(results)
            ..add(finishEvent).saveToResults(results);
        }

        test(
          'Close immediately',
          () => fakeAsync((async) {
            addEvents();

            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, Duration.zero);

            expect(conveyor.log.log, [
              '[init] removed $RemovedFromQueueManually()',
              '[incrementA] removed $RemovedFromQueueManually()',
              '[incrementB] removed $RemovedFromQueueManually()',
              '[finish] removed $RemovedFromQueueManually()',
            ]);

            expect(resultsToStrings(), [
              '[init] $RemovedFromQueueManually()',
              '[incrementA] $RemovedFromQueueManually()',
              '[incrementB] $RemovedFromQueueManually()',
              '[finish] $RemovedFromQueueManually()',
            ]);
          }),
        );

        test(
          'Close by microtask',
          () => fakeAsync((async) {
            addEvents();

            Future.microtask(conveyor.close);
            async.waitFuture(awaitResults());

            expect(async.elapsed, Duration.zero);

            expect(conveyor.log.log, [
              '[init] started',
              '[incrementA] removed $RemovedFromQueueManually()',
              '[incrementB] removed $RemovedFromQueueManually()',
              '[finish] removed $RemovedFromQueueManually()',
              '[init] cancelled $CancelledManually()',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledManually()',
              '[incrementA] $RemovedFromQueueManually()',
              '[incrementB] $RemovedFromQueueManually()',
              '[finish] $RemovedFromQueueManually()',
            ]);
          }),
        );

        test(
          'Close after 50 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 50));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 100));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              '[incrementA] removed $RemovedFromQueueManually()',
              '[incrementB] removed $RemovedFromQueueManually()',
              '[finish] removed $RemovedFromQueueManually()',
              '[init] cancelled $CancelledManually()',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledManually()',
              '[incrementA] $RemovedFromQueueManually()',
              '[incrementB] $RemovedFromQueueManually()',
              '[finish] $RemovedFromQueueManually()',
            ]);
          }),
        );

        test(
          'Close after 150 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 150));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 200));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              '[incrementA] removed $RemovedFromQueueManually()',
              '[incrementB] removed $RemovedFromQueueManually()',
              '[finish] removed $RemovedFromQueueManually()',
              '[init] cancelled $CancelledManually()',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledManually()',
              '[incrementA] $RemovedFromQueueManually()',
              '[incrementB] $RemovedFromQueueManually()',
              '[finish] $RemovedFromQueueManually()',
            ]);
          }),
        );

        test(
          'Close after 250 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 250));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 300));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              '[incrementA] removed $RemovedFromQueueManually()',
              '[incrementB] removed $RemovedFromQueueManually()',
              '[finish] removed $RemovedFromQueueManually()',
              '[init] cancelled $CancelledManually()',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledManually()',
              '[incrementA] $RemovedFromQueueManually()',
              '[incrementB] $RemovedFromQueueManually()',
              '[finish] $RemovedFromQueueManually()',
            ]);
          }),
        );

        test(
          'Close after 350 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 350));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 400));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              '[incrementB] removed $RemovedFromQueueManually()',
              '[finish] removed $RemovedFromQueueManually()',
              '[incrementA] cancelled $CancelledManually()',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] $CancelledManually()',
              '[incrementB] $RemovedFromQueueManually()',
              '[finish] $RemovedFromQueueManually()',
            ]);
          }),
        );

        test(
          'Close after 450 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 450));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 500));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              '[finish] removed $RemovedFromQueueManually()',
              '[incrementB] cancelled $CancelledManually()',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] $CancelledManually()',
              '[finish] $RemovedFromQueueManually()',
            ]);
          }),
        );

        test(
          'Close after 550 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 550));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 600));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              'state: $Working(a: 1, b: 1)',
              '[incrementB] done',
              '[finish] started',
              '[finish] cancelled $CancelledManually()',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] completed',
              '[finish] $CancelledManually()',
            ]);
          }),
        );

        test(
          'Close after 650 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 650));
            conveyor.close();
            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 650));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              'state: $Working(a: 1, b: 1)',
              '[incrementB] done',
              '[finish] started',
              'state: $Disposed()',
              '[finish] done',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] completed',
              '[finish] completed',
            ]);
          }),
        );
      });

      group('externalSetState.', () {
        void addEvents() {
          final initEvent = TestEvent<Initial, TestState>(
            key: 'init',
            // checkStateBeforeProcessing: (state) => state is Initial,
            // Отменяем при любом внешнем изменении состояния.
            checkStateOnExternalChange: (state) => false,
            (state) async* {
              yield const Preparing();

              await Future<void>.delayed(const Duration(milliseconds: 100));

              yield state
                  .isA<Preparing>()
                  .test((it) => it.progress == 0)
                  .use((it) => it.copyWith(progress: 50));

              await Future<void>.delayed(const Duration(milliseconds: 100));

              yield state
                  .isA<Preparing>()
                  .test((it) => it.progress == 50)
                  .use((it) => it.copyWith(progress: 100));

              await Future<void>.delayed(const Duration(milliseconds: 100));

              yield state
                  .isA<Preparing>()
                  .test((it) => it.progress == 100)
                  .use((_) => const Working());
            },
          );
          final incrementAEvent = TestEvent<Working, Working>(
            key: 'incrementA',
            (state) async* {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              yield state.use((it) => it.copyWith(a: it.a + 1));
            },
          );
          final incrementBEvent = TestEvent<Working, Working>(
            key: 'incrementB',
            (state) async* {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              yield state.use((it) => it.copyWith(b: it.b + 1));
            },
          );
          final finishEvent = TestEvent<TestState, Disposed>(
            key: 'finish',
            checkStateBeforeProcessing: (state) => state is! Disposed,
            checkStateOnExternalChange: (state) => state is! Disposed,
            (state) async* {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              yield const Disposed();
            },
          );

          conveyor.queue
            ..add(initEvent).saveToResults(results)
            ..add(incrementAEvent).saveToResults(results)
            ..add(incrementBEvent).saveToResults(results)
            ..add(finishEvent).saveToResults(results);
        }

        test(
          'Change state immediately',
          () => fakeAsync((async) {
            addEvents();

            conveyor.externalSetState(const Disposed());
            async.waitFuture(awaitResults());

            expect(async.elapsed, Duration.zero);

            expect(conveyor.log.log, [
              'state: $Disposed()',
              '[init] removed $RemovedFromQueueByEventRules()',
              '[incrementA] removed $RemovedFromQueueByEventRules()',
              '[incrementB] removed $RemovedFromQueueByEventRules()',
              '[finish] removed $RemovedFromQueueByEventRules()',
            ]);

            expect(resultsToStrings(), [
              '[init] $RemovedFromQueueByEventRules()',
              '[incrementA] $RemovedFromQueueByEventRules()',
              '[incrementB] $RemovedFromQueueByEventRules()',
              '[finish] $RemovedFromQueueByEventRules()',
            ]);
          }),
        );

        test(
          'Change state by microtask',
          () => fakeAsync((async) {
            addEvents();

            Future.microtask(() {
              conveyor.externalSetState(const Disposed());
            });
            async.waitFuture(awaitResults());

            expect(async.elapsed, Duration.zero);

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Disposed()',
              '[init] cancelled $CancelledByEventRulesOnExternalChange()',
              '[incrementA] removed $RemovedFromQueueByEventRules()',
              '[incrementB] removed $RemovedFromQueueByEventRules()',
              '[finish] removed $RemovedFromQueueByEventRules()',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledByEventRulesOnExternalChange()',
              '[incrementA] $RemovedFromQueueByEventRules()',
              '[incrementB] $RemovedFromQueueByEventRules()',
              '[finish] $RemovedFromQueueByEventRules()',
            ]);
          }),
        );

        test(
          'Change state after 50 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 50));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 100));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Disposed()',
              '[init] cancelled $CancelledByEventRulesOnExternalChange()',
              '[incrementA] removed $RemovedFromQueueByEventRules()',
              '[incrementB] removed $RemovedFromQueueByEventRules()',
              '[finish] removed $RemovedFromQueueByEventRules()',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledByEventRulesOnExternalChange()',
              '[incrementA] $RemovedFromQueueByEventRules()',
              '[incrementB] $RemovedFromQueueByEventRules()',
              '[finish] $RemovedFromQueueByEventRules()',
            ]);
          }),
        );

        test(
          'Change state after 150 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 150));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 200));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Disposed()',
              '[init] cancelled $CancelledByEventRulesOnExternalChange()',
              '[incrementA] removed $RemovedFromQueueByEventRules()',
              '[incrementB] removed $RemovedFromQueueByEventRules()',
              '[finish] removed $RemovedFromQueueByEventRules()',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledByEventRulesOnExternalChange()',
              '[incrementA] $RemovedFromQueueByEventRules()',
              '[incrementB] $RemovedFromQueueByEventRules()',
              '[finish] $RemovedFromQueueByEventRules()',
            ]);
          }),
        );

        test(
          'Change state after 250 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 250));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 300));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Disposed()',
              '[init] cancelled $CancelledByEventRulesOnExternalChange()',
              '[incrementA] removed $RemovedFromQueueByEventRules()',
              '[incrementB] removed $RemovedFromQueueByEventRules()',
              '[finish] removed $RemovedFromQueueByEventRules()',
            ]);

            expect(resultsToStrings(), [
              '[init] $CancelledByEventRulesOnExternalChange()',
              '[incrementA] $RemovedFromQueueByEventRules()',
              '[incrementB] $RemovedFromQueueByEventRules()',
              '[finish] $RemovedFromQueueByEventRules()',
            ]);
          }),
        );

        test(
          'Change state after 350 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 350));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 400));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Disposed()',
              // ignore: lines_longer_than_80_chars
              '[incrementA] cancelled $CancelledByEventRulesOnExternalChange()',
              '[incrementB] removed $RemovedFromQueueByEventRules()',
              '[finish] removed $RemovedFromQueueByEventRules()',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] $CancelledByEventRulesOnExternalChange()',
              '[incrementB] $RemovedFromQueueByEventRules()',
              '[finish] $RemovedFromQueueByEventRules()',
            ]);
          }),
        );

        test(
          'Change state after 450 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 450));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 500));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              'state: $Disposed()',
              // ignore: lines_longer_than_80_chars
              '[incrementB] cancelled $CancelledByEventRulesOnExternalChange()',
              '[finish] removed $RemovedFromQueueByEventRules()',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] $CancelledByEventRulesOnExternalChange()',
              '[finish] $RemovedFromQueueByEventRules()',
            ]);
          }),
        );

        test(
          'Change state after 550 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 550));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 600));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              'state: $Working(a: 1, b: 1)',
              '[incrementB] done',
              '[finish] started',
              'state: $Disposed()',
              '[finish] cancelled $CancelledByEventRulesOnExternalChange()',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] completed',
              '[finish] $CancelledByEventRulesOnExternalChange()',
            ]);
          }),
        );

        test(
          'Change state after 650 ms',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 650));
            conveyor.externalSetState(const Disposed());

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 650));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              'state: $Working(a: 1, b: 1)',
              '[incrementB] done',
              '[finish] started',
              'state: $Disposed()',
              '[finish] done',
              'state: $Disposed()',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] completed',
              '[finish] completed',
            ]);
          }),
        );

        test(
          'Change state during incrementA',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 350));
            conveyor.externalSetState(const Working(a: 10, b: 10));

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 600));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 10, b: 10)',
              'state: $Working(a: 11, b: 10)',
              '[incrementA] done',
              '[incrementB] started',
              'state: $Working(a: 11, b: 11)',
              '[incrementB] done',
              '[finish] started',
              'state: $Disposed()',
              '[finish] done',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] completed',
              '[finish] completed',
            ]);
          }),
        );

        test(
          'Change state during incrementB',
          () => fakeAsync((async) {
            addEvents();

            async.elapse(const Duration(milliseconds: 450));
            conveyor.externalSetState(const Working(a: 10, b: 10));

            async.waitFuture(awaitResults());

            expect(async.elapsed, const Duration(milliseconds: 600));

            expect(conveyor.log.log, [
              '[init] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 50)',
              'state: $Preparing(progress: 100)',
              'state: $Working(a: 0, b: 0)',
              '[init] done',
              '[incrementA] started',
              'state: $Working(a: 1, b: 0)',
              '[incrementA] done',
              '[incrementB] started',
              'state: $Working(a: 10, b: 10)',
              'state: $Working(a: 10, b: 11)',
              '[incrementB] done',
              '[finish] started',
              'state: $Disposed()',
              '[finish] done',
            ]);

            expect(resultsToStrings(), [
              '[init] completed',
              '[incrementA] completed',
              '[incrementB] completed',
              '[finish] completed',
            ]);
          }),
        );

        test(
          'Extremal test',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'extremalTest',
              (state) async* {
                conveyor.externalSetState(const Working());
                scheduleMicrotask(() {
                  debug('microtask');
                  conveyor.externalSetState(const Working(a: 2, b: 2));
                });
                yield state.isA<Working>().use((it) => it.copyWith(a: 1, b: 1));
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            // async.flushMicrotasks();

            expect(async.elapsed, Duration.zero);

            expect(conveyor.log.log, [
              '[extremalTest] started',
              'state: $Working(a: 0, b: 0)',
              'state: $Working(a: 1, b: 1)',
              'state: $Working(a: 2, b: 2)',
              '[extremalTest] done',
            ]);

            expect(resultsToStrings(), [
              '[extremalTest] completed',
            ]);
          }),
        );
      });

      group('WorkingState.', () {
        void addEvents() {
          final event1 = TestEvent<Initial, TestState>(
            key: 'test1',
            (state) async* {},
          );
          final event2 = TestEvent<Preparing, TestState>(
            key: 'test2',
            (state) async* {},
          );
          final event3 = TestEvent<Working, TestState>(
            key: 'test3',
            (state) async* {},
          );

          conveyor.queue
            ..add(event1).saveToResults(results)
            ..add(event2).saveToResults(results)
            ..add(event3).saveToResults(results);
        }

        test(
          'Initial',
          () => fakeAsync((async) {
            addEvents();
            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              '[test1] done',
              '[test2] removed $RemovedFromQueueByEventRules()',
              '[test3] removed $RemovedFromQueueByEventRules()',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] $RemovedFromQueueByEventRules()',
              '[test3] $RemovedFromQueueByEventRules()',
            ]);
          }),
        );

        test(
          'Preparing',
          () => fakeAsync((async) {
            conveyor.externalSetState(const Preparing());
            addEvents();
            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              'state: $Preparing(progress: 0)',
              '[test1] removed $RemovedFromQueueByEventRules()',
              '[test2] started',
              '[test2] done',
              '[test3] removed $RemovedFromQueueByEventRules()',
            ]);

            expect(resultsToStrings(), [
              '[test1] $RemovedFromQueueByEventRules()',
              '[test2] completed',
              '[test3] $RemovedFromQueueByEventRules()',
            ]);
          }),
        );

        test(
          'Working',
          () => fakeAsync((async) {
            conveyor.externalSetState(const Working());
            addEvents();
            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              'state: $Working(a: 0, b: 0)',
              '[test1] removed $RemovedFromQueueByEventRules()',
              '[test2] removed $RemovedFromQueueByEventRules()',
              '[test3] started',
              '[test3] done',
            ]);

            expect(resultsToStrings(), [
              '[test1] $RemovedFromQueueByEventRules()',
              '[test2] $RemovedFromQueueByEventRules()',
              '[test3] completed',
            ]);
          }),
        );

        test(
          'Disposed',
          () => fakeAsync((async) {
            conveyor.externalSetState(const Disposed());
            addEvents();
            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              'state: $Disposed()',
              '[test1] removed $RemovedFromQueueByEventRules()',
              '[test2] removed $RemovedFromQueueByEventRules()',
              '[test3] removed $RemovedFromQueueByEventRules()',
            ]);

            expect(resultsToStrings(), [
              '[test1] $RemovedFromQueueByEventRules()',
              '[test2] $RemovedFromQueueByEventRules()',
              '[test3] $RemovedFromQueueByEventRules()',
            ]);
          }),
        );

        test(
          'Initial > Preparing > Working > Disposed',
          () => fakeAsync((async) {
            final event1 = TestEvent<Initial, TestState>(
              key: 'test1',
              (state) async* {
                yield const Preparing();
              },
            );
            final event2 = TestEvent<Preparing, TestState>(
              key: 'test2',
              (state) async* {
                yield const Working();
              },
            );
            final event3 = TestEvent<Working, TestState>(
              key: 'test3',
              (state) async* {
                yield const Disposed();
              },
            );

            conveyor.queue
              ..add(event1).saveToResults(results)
              ..add(event2).saveToResults(results)
              ..add(event3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test1] started',
              'state: $Preparing(progress: 0)',
              '[test1] done',
              '[test2] started',
              'state: $Working(a: 0, b: 0)',
              '[test2] done',
              '[test3] started',
              'state: $Disposed()',
              '[test3] done',
            ]);

            expect(resultsToStrings(), [
              '[test1] completed',
              '[test2] completed',
              '[test3] completed',
            ]);
          }),
        );
      });

      group('State provider.', () {
        test(
          'value',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not Initial)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not Initial)',
            ]);
          }),
        );

        test(
          'use',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not Initial)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not Initial)',
            ]);
          }),
        );

        test(
          'test.value',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.test((it) => true).value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not Initial)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not Initial)',
            ]);
          }),
        );

        test(
          'test.use',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.test((it) => true).use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not Initial)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not Initial)',
            ]);
          }),
        );

        test(
          'map.value',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.map<Working>((_) => const Working()).value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not Initial)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not Initial)',
            ]);
          }),
        );

        test(
          'map.use',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state
                    .map<Working>((_) => const Working())
                    .use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not Initial)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not Initial)',
            ]);
          }),
        );

        test(
          'strongMap.value',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.strongMap((it) => it).value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not Initial)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not Initial)',
            ]);
          }),
        );

        test(
          'strongMap.use',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.strongMap((it) => it).use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not Initial)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not Initial)',
            ]);
          }),
        );

        test(
          'isA.value',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.use',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.test.value',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .test((it) => it.progress == 0)
                    .value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.test.use',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .test((it) => it.progress == 0)
                    .use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.map.value',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .map<Working>((it) => const Working())
                    .value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Working(a: 0, b: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.map.use',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .map<Working>((it) => const Working())
                    .use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Working(a: 0, b: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.strongMap.value',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .strongMap((it) => it.copyWith(progress: 100))
                    .value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 100)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.strongMap.use',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .strongMap((it) => it.copyWith(progress: 100))
                    .use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 100)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.isA<Preparing>.value',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<Preparing>().value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.isA<Preparing>.use',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<Preparing>().use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.isA<Working>.value',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<Working>().value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not Working)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not Working)',
            ]);
          }),
        );

        test(
          'isA.isA<Working>.use',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<Working>().use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not Working)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not Working)',
            ]);
          }),
        );

        test(
          'isA.isA<TestState>.value',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<TestState>().value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.isA<TestState>.use',
          () => fakeAsync((async) {
            final event = TestEvent<Initial, TestState>(
              key: 'test',
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<TestState>().use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );
      });

      group('State provider + checkStateBeforeProcessing.', () {
        test(
          'value',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'test.value',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.test((it) => true).value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'test.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.test((it) => true).use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'map.value',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.map<Working>((_) => const Working()).value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Working(a: 0, b: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'map.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state
                    .map<Working>((_) => const Working())
                    .use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Working(a: 0, b: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'strongMap.value',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.strongMap((it) => it).value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'strongMap.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.strongMap((it) => it).use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.value',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.test.value',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .test((it) => it.progress == 0)
                    .value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.test.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .test((it) => it.progress == 0)
                    .use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.map.value',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .map<Working>((it) => const Working())
                    .value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Working(a: 0, b: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.map.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .map<Working>((it) => const Working())
                    .use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Working(a: 0, b: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.strongMap.value',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .strongMap((it) => it.copyWith(progress: 100))
                    .value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 100)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.strongMap.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state
                    .isA<Preparing>()
                    .strongMap((it) => it.copyWith(progress: 100))
                    .use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 100)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.isA<Preparing>.value',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<Preparing>().value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.isA<Preparing>.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<Preparing>().use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.isA<Working>.value',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<Working>().value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not Working)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not Working)',
            ]);
          }),
        );

        test(
          'isA.isA<Working>.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<Working>().use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              '[test] cancelled $CancelledByCheckState(is not Working)',
            ]);

            expect(resultsToStrings(), [
              '[test] $CancelledByCheckState(is not Working)',
            ]);
          }),
        );

        test(
          'isA.isA<TestState>.value',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<TestState>().value;
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );

        test(
          'isA.isA<TestState>.use',
          () => fakeAsync((async) {
            final event = TestEvent<TestState, TestState>(
              key: 'test',
              checkStateBeforeProcessing: (state) => state is Initial,
              (state) async* {
                yield const Preparing();
                yield state.isA<Preparing>().isA<TestState>().use((it) => it);
              },
            );

            conveyor.queue.add(event).saveToResults(results);

            async.waitFuture(awaitResults());

            expect(conveyor.log.log, [
              '[test] started',
              'state: $Preparing(progress: 0)',
              'state: $Preparing(progress: 0)',
              '[test] done',
            ]);

            expect(resultsToStrings(), [
              '[test] completed',
            ]);
          }),
        );
      });
    });

    group('Queue.', () {
      TestEvent<TestState, TestState> noop(int num) {
        final event = TestEvent<Special, Special>(
          key: 'noop$num',
          (state) async* {
            await Future(() {});
            yield state.use(
              (it) => it.copyWith(
                noopCount: it.noopCount + 1,
              ),
            );
          },
        );

        conveyor.queue.add(event);

        return event;
      }

      TestEvent<TestState, TestState> sequential(int num) {
        final event = TestEvent<Special, Special>(
          key: 'sequential$num',
          (state) async* {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            yield state.use(
              (state) => state.copyWith(
                sequentialCount: state.sequentialCount + 1,
              ),
            );
          },
        );

        conveyor.queue.add(event);

        return event;
      }

      TestEvent<TestState, TestState> droppable(int num) =>
          conveyor.addEventOrDrop(
            check: (e) => e.key.startsWith('droppable'),
            create: () => TestEvent<Special, Special>(
              key: 'droppable$num',
              (state) async* {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                yield state.use(
                  (it) => it.copyWith(
                    droppableCount: it.droppableCount + 1,
                  ),
                );
              },
            ),
          );

      TestEvent<TestState, TestState> droppableReturnPrevious(int num) =>
          conveyor.addEventOrDrop(
            returnPreviousIfExists: true,
            check: (e) => e.key.startsWith('droppable'),
            create: () => TestEvent<Special, Special>(
              key: 'droppable$num',
              (state) async* {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                yield state.use(
                  (it) => it.copyWith(
                    droppableCount: it.droppableCount + 1,
                  ),
                );
              },
            ),
          );

      TestEvent<TestState, TestState> restartable(int num) =>
          conveyor.addEventAndRestart(
            check: (e) => e.key.startsWith('restartable'),
            create: () => TestEvent<Special, Special>(
              key: 'restartable$num',
              (state) async* {
                yield state.use(
                  (state) => state.copyWith(
                    restartableCount: state.restartableCount + 1,
                  ),
                );
                await Future<void>.delayed(const Duration(milliseconds: 100));
                yield state.use(
                  (state) => state.copyWith(
                    restartableCount: state.restartableCount + 1,
                  ),
                );
              },
            ),
          );

      setUp(() {
        conveyor.externalSetState(const Special());
      });

      group('Sequential.', () {
        test(
          'One by one',
          () => fakeAsync((async) {
            sequential(1).saveToResults(results);
            sequential(2).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).sequentialCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[sequential1] started',
              'state: $Special(sequential: 1)',
              '[sequential1] done',
              '[sequential2] started',
              'state: $Special(sequential: 2)',
              '[sequential2] done',
            ]);

            expect(resultsToStrings(), [
              '[sequential1] completed',
              '[sequential2] completed',
            ]);
          }),
        );

        test(
          'One by one with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            sequential(1).saveToResults(results);
            noop(2).saveToResults(results);
            sequential(2).saveToResults(results);
            noop(3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).sequentialCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[sequential1] started',
              'state: $Special(noop: 1, sequential: 1)',
              '[sequential1] done',
              '[noop2] started',
              'state: $Special(noop: 2, sequential: 1)',
              '[noop2] done',
              '[sequential2] started',
              'state: $Special(noop: 2, sequential: 2)',
              '[sequential2] done',
              '[noop3] started',
              'state: $Special(noop: 3, sequential: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[sequential1] completed',
              '[noop2] completed',
              '[sequential2] completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A little pause between',
          () => fakeAsync((async) {
            sequential(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            sequential(2).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).sequentialCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[sequential1] started',
              'state: $Special(sequential: 1)',
              '[sequential1] done',
              '[sequential2] started',
              'state: $Special(sequential: 2)',
              '[sequential2] done',
            ]);

            expect(resultsToStrings(), [
              '[sequential1] completed',
              '[sequential2] completed',
            ]);
          }),
        );

        test(
          'A little pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            sequential(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            sequential(2).saveToResults(results);
            noop(3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).sequentialCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[sequential1] started',
              'state: $Special(noop: 1, sequential: 1)',
              '[sequential1] done',
              '[noop2] started',
              'state: $Special(noop: 2, sequential: 1)',
              '[noop2] done',
              '[sequential2] started',
              'state: $Special(noop: 2, sequential: 2)',
              '[sequential2] done',
              '[noop3] started',
              'state: $Special(noop: 3, sequential: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[sequential1] completed',
              '[noop2] completed',
              '[sequential2] completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A big pause between',
          () => fakeAsync((async) {
            sequential(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            sequential(2).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).sequentialCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[sequential1] started',
              'state: $Special(sequential: 1)',
              '[sequential1] done',
              '[sequential2] started',
              'state: $Special(sequential: 2)',
              '[sequential2] done',
            ]);

            expect(resultsToStrings(), [
              '[sequential1] completed',
              '[sequential2] completed',
            ]);
          }),
        );

        test(
          'A big pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            sequential(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            sequential(2).saveToResults(results);
            noop(3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).sequentialCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[sequential1] started',
              'state: $Special(noop: 1, sequential: 1)',
              '[sequential1] done',
              '[noop2] started',
              'state: $Special(noop: 2, sequential: 1)',
              '[noop2] done',
              '[sequential2] started',
              'state: $Special(noop: 2, sequential: 2)',
              '[sequential2] done',
              '[noop3] started',
              'state: $Special(noop: 3, sequential: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[sequential1] completed',
              '[noop2] completed',
              '[sequential2] completed',
              '[noop3] completed',
            ]);
          }),
        );
      });

      group('Droppable.', () {
        test(
          'One by one',
          () => fakeAsync((async) {
            droppable(1).saveToResults(results);
            droppable(2).saveToResults(results);

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[droppable2] removed $RemovedFromQueueManually()',
              '[droppable1] started',
              'state: $Special(droppable: 1)',
              '[droppable1] done',
            ]);

            expect(resultsToStrings(), [
              '[droppable1] completed',
              '[droppable2] $RemovedFromQueueManually()',
            ]);
          }),
        );

        test(
          'One by one with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            droppable(1).saveToResults(results);
            noop(2).saveToResults(results);
            droppable(2).saveToResults(results);
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[droppable2] removed $RemovedFromQueueManually()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[droppable1] started',
              'state: $Special(noop: 1, droppable: 1)',
              '[droppable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, droppable: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, droppable: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[droppable1] completed',
              '[noop2] completed',
              '[droppable2] $RemovedFromQueueManually()',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A little pause between',
          () => fakeAsync((async) {
            droppable(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            droppable(2).saveToResults(results);

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[droppable1] started',
              '[droppable2] removed $RemovedFromQueueManually()',
              'state: $Special(droppable: 1)',
              '[droppable1] done',
            ]);

            expect(resultsToStrings(), [
              '[droppable1] completed',
              '[droppable2] RemovedFromQueueManually()',
            ]);
          }),
        );

        test(
          'A little pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            droppable(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            droppable(2).saveToResults(results);
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[droppable1] started',
              '[droppable2] removed $RemovedFromQueueManually()',
              'state: $Special(noop: 1, droppable: 1)',
              '[droppable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, droppable: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, droppable: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[droppable1] completed',
              '[noop2] completed',
              '[droppable2] RemovedFromQueueManually()',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A big pause between',
          () => fakeAsync((async) {
            droppable(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            droppable(2).saveToResults(results);

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[droppable1] started',
              'state: $Special(droppable: 1)',
              '[droppable1] done',
              '[droppable2] started',
              'state: $Special(droppable: 2)',
              '[droppable2] done',
            ]);

            expect(resultsToStrings(), [
              '[droppable1] completed',
              '[droppable2] completed',
            ]);
          }),
        );

        test(
          'A big pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            droppable(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            droppable(2).saveToResults(results);
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[droppable1] started',
              'state: $Special(noop: 1, droppable: 1)',
              '[droppable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, droppable: 1)',
              '[noop2] done',
              '[droppable2] started',
              'state: $Special(noop: 2, droppable: 2)',
              '[droppable2] done',
              '[noop3] started',
              'state: $Special(noop: 3, droppable: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[droppable1] completed',
              '[noop2] completed',
              '[droppable2] completed',
              '[noop3] completed',
            ]);
          }),
        );
      });

      group('Droppable with return previous event when dropped.', () {
        test(
          'One by one',
          () => fakeAsync((async) {
            droppableReturnPrevious(1).saveToResults(results, '#1');
            droppableReturnPrevious(2).saveToResults(results, '#2');

            expect(identicalResults(0, 1), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[droppable1] started',
              'state: $Special(droppable: 1)',
              '[droppable1] done',
            ]);

            expect(resultsToStrings(), [
              '[droppable1]#1 completed',
              '[droppable1]#2 completed',
            ]);
          }),
        );

        test(
          'One by one with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            droppableReturnPrevious(1).saveToResults(results, '#1');
            noop(2).saveToResults(results);
            droppableReturnPrevious(2).saveToResults(results, '#2');
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[droppable1] started',
              'state: $Special(noop: 1, droppable: 1)',
              '[droppable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, droppable: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, droppable: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[droppable1]#1 completed',
              '[noop2] completed',
              '[droppable1]#2 completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A little pause between',
          () => fakeAsync((async) {
            droppableReturnPrevious(1).saveToResults(results, '#1');
            async.elapse(const Duration(milliseconds: 50));
            droppableReturnPrevious(2).saveToResults(results, '#2');

            expect(identicalResults(0, 1), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[droppable1] started',
              'state: $Special(droppable: 1)',
              '[droppable1] done',
            ]);

            expect(resultsToStrings(), [
              '[droppable1]#1 completed',
              '[droppable1]#2 completed',
            ]);
          }),
        );

        test(
          'A little pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            droppableReturnPrevious(1).saveToResults(results, '#1');
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            droppableReturnPrevious(2).saveToResults(results, '#2');
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[droppable1] started',
              'state: $Special(noop: 1, droppable: 1)',
              '[droppable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, droppable: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, droppable: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[droppable1]#1 completed',
              '[noop2] completed',
              '[droppable1]#2 completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A big pause between',
          () => fakeAsync((async) {
            droppableReturnPrevious(1).saveToResults(results, '#1');
            async.elapse(const Duration(milliseconds: 150));
            droppableReturnPrevious(2).saveToResults(results, '#2');

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[droppable1] started',
              'state: $Special(droppable: 1)',
              '[droppable1] done',
              '[droppable2] started',
              'state: $Special(droppable: 2)',
              '[droppable2] done',
            ]);

            expect(resultsToStrings(), [
              '[droppable1]#1 completed',
              '[droppable2]#2 completed',
            ]);
          }),
        );

        test(
          'A big pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            droppableReturnPrevious(1).saveToResults(results, '#1');
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            droppableReturnPrevious(2).saveToResults(results, '#2');
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).droppableCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[droppable1] started',
              'state: $Special(noop: 1, droppable: 1)',
              '[droppable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, droppable: 1)',
              '[noop2] done',
              '[droppable2] started',
              'state: $Special(noop: 2, droppable: 2)',
              '[droppable2] done',
              '[noop3] started',
              'state: $Special(noop: 3, droppable: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[droppable1]#1 completed',
              '[noop2] completed',
              '[droppable2]#2 completed',
              '[noop3] completed',
            ]);
          }),
        );
      });

      group('Restartable.', () {
        test(
          'One by one',
          () => fakeAsync((async) {
            restartable(1).saveToResults(results);
            restartable(2).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).restartableCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[restartable1] removed $RemovedFromQueueManually()',
              '[restartable2] started',
              'state: $Special(restartable: 1)',
              'state: $Special(restartable: 2)',
              '[restartable2] done',
            ]);

            expect(resultsToStrings(), [
              '[restartable1] $RemovedFromQueueManually()',
              '[restartable2] completed',
            ]);
          }),
        );

        test(
          'One by one with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            restartable(1).saveToResults(results);
            noop(2).saveToResults(results);
            restartable(2).saveToResults(results);
            noop(3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).restartableCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[restartable1] removed $RemovedFromQueueManually()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[noop2] started',
              'state: $Special(noop: 2)',
              '[noop2] done',
              '[restartable2] started',
              'state: $Special(noop: 2, restartable: 1)',
              'state: $Special(noop: 2, restartable: 2)',
              '[restartable2] done',
              '[noop3] started',
              'state: $Special(noop: 3, restartable: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[restartable1] $RemovedFromQueueManually()',
              '[noop2] completed',
              '[restartable2] completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A little pause between',
          () => fakeAsync((async) {
            restartable(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            restartable(2).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).restartableCount, 3);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[restartable1] started',
              'state: $Special(restartable: 1)',
              '[restartable1] cancelled $CancelledManually()',
              '[restartable2] started',
              'state: $Special(restartable: 2)',
              'state: $Special(restartable: 3)',
              '[restartable2] done',
            ]);

            expect(resultsToStrings(), [
              '[restartable1] $CancelledManually()',
              '[restartable2] completed',
            ]);
          }),
        );

        test(
          'A little pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            restartable(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            restartable(2).saveToResults(results);
            noop(3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).restartableCount, 3);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[restartable1] started',
              'state: $Special(noop: 1, restartable: 1)',
              '[restartable1] cancelled $CancelledManually()',
              '[noop2] started',
              'state: $Special(noop: 2, restartable: 1)',
              '[noop2] done',
              '[restartable2] started',
              'state: $Special(noop: 2, restartable: 2)',
              'state: $Special(noop: 2, restartable: 3)',
              '[restartable2] done',
              '[noop3] started',
              'state: $Special(noop: 3, restartable: 3)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[restartable1] $CancelledManually()',
              '[noop2] completed',
              '[restartable2] completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A big pause between',
          () => fakeAsync((async) {
            restartable(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            restartable(2).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).restartableCount, 4);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[restartable1] started',
              'state: $Special(restartable: 1)',
              'state: $Special(restartable: 2)',
              '[restartable1] done',
              '[restartable2] started',
              'state: $Special(restartable: 3)',
              'state: $Special(restartable: 4)',
              '[restartable2] done',
            ]);

            expect(resultsToStrings(), [
              '[restartable1] completed',
              '[restartable2] completed',
            ]);
          }),
        );

        test(
          'A big pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            restartable(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            restartable(2).saveToResults(results);
            noop(3).saveToResults(results);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).restartableCount, 4);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[restartable1] started',
              'state: $Special(noop: 1, restartable: 1)',
              'state: $Special(noop: 1, restartable: 2)',
              '[restartable1] done',
              '[noop2] started',
              'state: $Special(noop: 2, restartable: 2)',
              '[noop2] done',
              '[restartable2] started',
              'state: $Special(noop: 2, restartable: 3)',
              'state: $Special(noop: 2, restartable: 4)',
              '[restartable2] done',
              '[noop3] started',
              'state: $Special(noop: 3, restartable: 4)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[restartable1] completed',
              '[noop2] completed',
              '[restartable2] completed',
              '[noop3] completed',
            ]);
          }),
        );
      });

      group('Debounce.', () {
        late Debouncer<void> debouncer;

        TestEvent<TestState, TestState> debounce(int num) {
          final lastEvent = conveyor.lastEventWhere(
            (e) => e.key.startsWith('debounce'),
          );

          final event = conveyor.queue.add(
            TestEvent<Special, Special>(
              key: 'debounce$num',
              (state) async* {
                yield state.use(
                  (state) => state.copyWith(
                    debounceCount: state.debounceCount + 1,
                  ),
                );
              },
            ),
          );

          if (lastEvent != null || !debouncer.start()) {
            event.unlink();
          }

          return event;
        }

        setUp(() {
          debouncer = Debouncer<void>(const Duration(milliseconds: 100));
        });

        test(
          'One by one',
          () => fakeAsync((async) {
            debounce(1).saveToResults(results);
            debounce(2).saveToResults(results);

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[debounce2] removed $RemovedFromQueueManually()',
              '[debounce1] started',
              'state: $Special(debounce: 1)',
              '[debounce1] done',
            ]);

            expect(resultsToStrings(), [
              '[debounce1] completed',
              '[debounce2] $RemovedFromQueueManually()',
            ]);
          }),
        );

        test(
          'One by one with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            debounce(1).saveToResults(results);
            noop(2).saveToResults(results);
            debounce(2).saveToResults(results);
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[debounce2] removed $RemovedFromQueueManually()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[debounce1] started',
              'state: $Special(noop: 1, debounce: 1)',
              '[debounce1] done',
              '[noop2] started',
              'state: $Special(noop: 2, debounce: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, debounce: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[debounce1] completed',
              '[noop2] completed',
              '[debounce2] $RemovedFromQueueManually()',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A little pause between',
          () => fakeAsync((async) {
            debounce(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            debounce(2).saveToResults(results);

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[debounce1] started',
              'state: $Special(debounce: 1)',
              '[debounce1] done',
              '[debounce2] removed $RemovedFromQueueManually()',
            ]);

            expect(resultsToStrings(), [
              '[debounce1] completed',
              '[debounce2] $RemovedFromQueueManually()',
            ]);
          }),
        );

        test(
          'A little pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            debounce(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            debounce(2).saveToResults(results);
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[debounce1] started',
              'state: $Special(noop: 1, debounce: 1)',
              '[debounce1] done',
              '[noop2] started',
              'state: $Special(noop: 2, debounce: 1)',
              '[noop2] done',
              '[debounce2] removed $RemovedFromQueueManually()',
              '[noop3] started',
              'state: $Special(noop: 3, debounce: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[debounce1] completed',
              '[noop2] completed',
              '[debounce2] $RemovedFromQueueManually()',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A big pause between',
          () => fakeAsync((async) {
            debounce(1).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            debounce(2).saveToResults(results);

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[debounce1] started',
              'state: $Special(debounce: 1)',
              '[debounce1] done',
              '[debounce2] started',
              'state: $Special(debounce: 2)',
              '[debounce2] done',
            ]);

            expect(resultsToStrings(), [
              '[debounce1] completed',
              '[debounce2] completed',
            ]);
          }),
        );

        test(
          'A big pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            debounce(1).saveToResults(results);
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            debounce(2).saveToResults(results);
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[debounce1] started',
              'state: $Special(noop: 1, debounce: 1)',
              '[debounce1] done',
              '[noop2] started',
              'state: $Special(noop: 2, debounce: 1)',
              '[noop2] done',
              '[debounce2] started',
              'state: $Special(noop: 2, debounce: 2)',
              '[debounce2] done',
              '[noop3] started',
              'state: $Special(noop: 3, debounce: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[debounce1] completed',
              '[noop2] completed',
              '[debounce2] completed',
              '[noop3] completed',
            ]);
          }),
        );
      });

      group('Debounce with return previous event when dropped.', () {
        late Debouncer<TestEvent<TestState, TestState>> debouncerWithPrevious;

        TestEvent<TestState, TestState> debounceReturnPrevious(int num) {
          final lastEvent = conveyor.lastEventWhere(
            (e) => e.key.startsWith('debounce'),
          );
          if (lastEvent != null) {
            return lastEvent;
          }

          return debouncerWithPrevious.startWithData(
            onStart: () => conveyor.queue.add(
              TestEvent<Special, Special>(
                key: 'debounce$num',
                (state) async* {
                  yield state.use(
                    (it) => it.copyWith(
                      debounceCount: it.debounceCount + 1,
                    ),
                  );
                },
              ),
            ),
          );
        }

        setUp(() {
          debouncerWithPrevious = Debouncer<TestEvent<TestState, TestState>>(
            const Duration(milliseconds: 100),
          );
        });

        test(
          'One by one',
          () => fakeAsync((async) {
            debounceReturnPrevious(1).saveToResults(results, '#1');
            debounceReturnPrevious(2).saveToResults(results, '#2');

            expect(identicalResults(0, 1), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[debounce1] started',
              'state: $Special(debounce: 1)',
              '[debounce1] done',
            ]);

            expect(resultsToStrings(), [
              '[debounce1]#1 completed',
              '[debounce1]#2 completed',
            ]);
          }),
        );

        test(
          'One by one with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            debounceReturnPrevious(1).saveToResults(results, '#1');
            noop(2).saveToResults(results);
            debounceReturnPrevious(2).saveToResults(results, '#2');
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[debounce1] started',
              'state: $Special(noop: 1, debounce: 1)',
              '[debounce1] done',
              '[noop2] started',
              'state: $Special(noop: 2, debounce: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, debounce: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[debounce1]#1 completed',
              '[noop2] completed',
              '[debounce1]#2 completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A little pause between',
          () => fakeAsync((async) {
            debounceReturnPrevious(1).saveToResults(results, '#1');
            async.elapse(const Duration(milliseconds: 50));
            debounceReturnPrevious(2).saveToResults(results, '#2');

            expect(identicalResults(0, 1), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[debounce1] started',
              'state: $Special(debounce: 1)',
              '[debounce1] done',
            ]);

            expect(resultsToStrings(), [
              '[debounce1]#1 completed',
              '[debounce1]#2 completed',
            ]);
          }),
        );

        test(
          'A little pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            debounceReturnPrevious(1).saveToResults(results, '#1');
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 50));
            debounceReturnPrevious(2).saveToResults(results, '#2');
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isTrue);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 1);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[debounce1] started',
              'state: $Special(noop: 1, debounce: 1)',
              '[debounce1] done',
              '[noop2] started',
              'state: $Special(noop: 2, debounce: 1)',
              '[noop2] done',
              '[noop3] started',
              'state: $Special(noop: 3, debounce: 1)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[debounce1]#1 completed',
              '[noop2] completed',
              '[debounce1]#2 completed',
              '[noop3] completed',
            ]);
          }),
        );

        test(
          'A big pause between',
          () => fakeAsync((async) {
            debounceReturnPrevious(1).saveToResults(results, '#1');
            async.elapse(const Duration(milliseconds: 150));
            debounceReturnPrevious(2).saveToResults(results, '#2');

            expect(identicalResults(0, 1), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[debounce1] started',
              'state: $Special(debounce: 1)',
              '[debounce1] done',
              '[debounce2] started',
              'state: $Special(debounce: 2)',
              '[debounce2] done',
            ]);

            expect(resultsToStrings(), [
              '[debounce1]#1 completed',
              '[debounce2]#2 completed',
            ]);
          }),
        );

        test(
          'A big pause between with other events',
          () => fakeAsync((async) {
            noop(1).saveToResults(results);
            debounceReturnPrevious(1).saveToResults(results, '#1');
            noop(2).saveToResults(results);
            async.elapse(const Duration(milliseconds: 150));
            debounceReturnPrevious(2).saveToResults(results, '#2');
            noop(3).saveToResults(results);

            expect(identicalResults(1, 3), isFalse);

            async.waitFuture(awaitResults());

            expect((conveyor.state as Special).debounceCount, 2);

            expect(conveyor.log.log, [
              'state: $Special()',
              '[noop1] started',
              'state: $Special(noop: 1)',
              '[noop1] done',
              '[debounce1] started',
              'state: $Special(noop: 1, debounce: 1)',
              '[debounce1] done',
              '[noop2] started',
              'state: $Special(noop: 2, debounce: 1)',
              '[noop2] done',
              '[debounce2] started',
              'state: $Special(noop: 2, debounce: 2)',
              '[debounce2] done',
              '[noop3] started',
              'state: $Special(noop: 3, debounce: 2)',
              '[noop3] done',
            ]);

            expect(resultsToStrings(), [
              '[noop1] completed',
              '[debounce1]#1 completed',
              '[noop2] completed',
              '[debounce2]#2 completed',
              '[noop3] completed',
            ]);
          }),
        );
      });
    });

    group('Inner events.', () {
      void addEvents() {
        final event3 = TestEvent<Preparing, Preparing>(
          key: 'test3',
          (state) async* {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            yield state.use((it) => it.copyWith(progress: 100));
          },
        );
        final event2 = TestEvent<Preparing, TestState>(
          key: 'test2',
          (state) async* {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            yield state.use((it) => it.copyWith(progress: 50));

            event3.saveToResults(results);
            yield* state.run(event3);

            yield const Working();
          },
        );
        final event1 = TestEvent<TestState, TestState>(
          key: 'test1',
          checkStateOnExternalChange: (state) => state is! Disposed,
          (state) async* {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            yield const Preparing();

            event2.saveToResults(results);
            yield* state.run(event2);

            yield const Disposed();
          },
        );

        conveyor.queue.add(event1).saveToResults(results);
      }

      test(
        'Simple test',
        () => fakeAsync((async) {
          addEvents();
          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Preparing(progress: 100)',
            '>> [test3] done',
            'state: $Working(a: 0, b: 0)',
            '> [test2] done',
            'state: $Disposed()',
            '[test1] done',
          ]);

          expect(resultsToStrings(), [
            '[test1] completed',
            '[test2] completed',
            '[test3] completed',
          ]);
        }),
      );

      test(
        'Close after 50 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 50), () {
            conveyor.currentProcess?.cancel();
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            '[test1] cancelled $CancelledManually()',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledManually()',
          ]);
        }),
      );

      test(
        'Close after 150 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 150), () {
            conveyor.currentProcess?.cancel();
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            '> [test2] cancelled $CancelledManually()',
            '[test1] cancelled $CancelledManually()',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledManually()',
            '[test2] $CancelledManually()',
          ]);
        }),
      );

      test(
        'Close after 250 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 250), () {
            conveyor.currentProcess?.cancel();
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            '>> [test3] cancelled $CancelledManually()',
            '> [test2] cancelled $CancelledManually()',
            '[test1] cancelled $CancelledManually()',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledManually()',
            '[test2] $CancelledManually()',
            '[test3] $CancelledManually()',
          ]);
        }),
      );

      test(
        'Change state to Disposed after 50 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 50), () {
            conveyor.externalSetState(const Disposed());
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: Disposed()',
            '[test1] cancelled $CancelledByEventRulesOnExternalChange()',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledByEventRulesOnExternalChange()',
          ]);
        }),
      );

      test(
        'Change state to Disposed after 150 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 150), () {
            conveyor.externalSetState(const Disposed());
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Disposed()',
            '> [test2] cancelled $CancelledManually()', // TODO(nashol): ???
            '[test1] cancelled $CancelledByEventRulesOnExternalChange()',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledByEventRulesOnExternalChange()',
            '[test2] $CancelledManually()',
          ]);
        }),
      );

      test(
        'Change state to Disposed after 250 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 250), () {
            conveyor.externalSetState(const Disposed());
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Disposed()',
            '>> [test3] cancelled $CancelledManually()',
            '> [test2] cancelled $CancelledManually()',
            '[test1] cancelled $CancelledByEventRulesOnExternalChange()',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledByEventRulesOnExternalChange()',
            '[test2] $CancelledManually()',
            '[test3] $CancelledManually()',
          ]);
        }),
      );

      test(
        'Change state to Working after 250 ms',
        () => fakeAsync((async) {
          addEvents();

          Future<void>.delayed(const Duration(milliseconds: 250), () {
            conveyor.externalSetState(const Working());
          });

          async.waitFuture(awaitResults());

          expect(conveyor.log.log, [
            '[test1] started',
            'state: $Preparing(progress: 0)',
            '> [test2] started',
            'state: $Preparing(progress: 50)',
            '>> [test3] started',
            'state: $Working(a: 0, b: 0)',
            '>> [test3] cancelled $CancelledByCheckState(is not Preparing)',
            '> [test2] cancelled $CancelledByCheckState(is not Preparing)',
            '[test1] cancelled $CancelledByCheckState(is not Preparing)',
          ]);

          expect(resultsToStrings(), [
            '[test1] $CancelledByCheckState(is not Preparing)',
            '[test2] $CancelledByCheckState(is not Preparing)',
            '[test3] $CancelledByCheckState(is not Preparing)',
          ]);
        }),
      );
    });
  });
}
