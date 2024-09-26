import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

part 'event.dart';
part 'exceptions/cancelled.dart';
part 'mixins.dart';
part 'process.dart';
part 'queue.dart';
part 'result.dart';

abstract class Conveyor<S extends Object, E extends ConveyorEvent<S, E>> {
  late final ConveyorQueue<S, E> _queue;
  late final StreamController<S> _stateController;

  S _state;
  _ConveyorProcess<S, E>? _currentProcess;

  Conveyor(
    S initialState,
  ) : _state = initialState {
    _queue = ConveyorQueue(onOccurrenceEvent: _run);
    _stateController = StreamController.broadcast(sync: true);
  }

  Stream<S> get stream => _stateController.stream;

  @protected
  ConveyorQueue<S, E> get queue => _queue;

  @protected
  ConveyorProcess<S, E>? get currentProcess => _currentProcess;

  @protected
  bool get inProgress => _currentProcess != null;

  T state<T extends S>([bool Function(T state)? test]) {
    final state = _state;
    if (state is! T || test != null && !test(state)) {
      throw const CancelledByCheckState._();
    }

    return state;
  }

  void checkState<T extends S>([bool Function(T state)? test]) {
    state<T>(test);
  }

  void _setState(S newState) {
    print('* setState: $newState');

    _state = newState;
    _stateController.add(newState);
  }

  void _externalSetState(S newState) {
    print('* external setState: $newState');

    _setState(newState);

    final currentProcess = _currentProcess;
    if (currentProcess != null) {
      final checkState = currentProcess.event.checkState;
      if (checkState != null && !checkState(newState)) {
        currentProcess._cancel(const CancelledByEventContidion._());
      }
    }
  }

  @mustCallSuper
  Future<void> close() async {
    print('* close');

    _queue.clear();

    // При закрытии дожидаемся окончания текущего рабочего процесса.
    final currentProcess = _currentProcess;
    if (currentProcess != null) {
      await currentProcess.cancel();
    }

    await _stateController.close();
  }

  Future<void> awaitCurrentProccess() async {
    print('* awaitCurrentProccess');

    final currentProcess = _currentProcess;
    if (currentProcess != null) {
      await currentProcess.future;
    }
  }

  /// Запуск обработки событий, если обработка была прервана.
  void _run() {
    // При добавлении событий обработка не будет запущена синхронно. Даём
    // возможность коду, добавившему события, завершить свою синхронную часть.
    scheduleMicrotask(() {
      if (_currentProcess != null) {
        return;
      }

      print('* run');

      final item = _pull();
      if (item != null) {
        _handle(item.event);
      }
    });
  }

  FutureOr<void> onCancel(
    E event,
    Cancelled reason,
    StackTrace stackTrace,
  ) {
    print('* onCancel: $event $reason');
    // print('* onCancel: $event $reason\n$stackTrace'.replaceAll('\n', '\n  * '));
  }

  FutureOr<void> onError(
    E event,
    Object error,
    StackTrace stackTrace,
  ) {
    print('* onError: $event $error');
    // print('* onError: $event $error\n$stackTrace'.replaceAll('\n', '\n* * '));
  }

  /// Вынимает из очереди первый элемент, соответствующий текущему состоянию.
  ///
  /// Все элементы в очереди, предшествующие искомому элементу и не
  /// соответствующие текущему состоянию, удаляются с признаком
  /// [RemovedFromQueueByEventContidion].
  _ConveyorItem<S, E>? _pull() {
    if (_queue.isEmpty) {
      return null;
    }

    var nextItem = _queue._unsafePull();
    while (nextItem != null) {
      final checkState =
          nextItem.event.checkInitialState ?? nextItem.event.checkState;
      if (checkState == null || checkState(_state)) {
        return nextItem;
      } else {
        nextItem.event._result._cancel(
          const RemovedFromQueueByEventContidion._(),
          StackTrace.current,
        );

        print('* event removed: ${nextItem.event} ${nextItem.event.result}');

        nextItem = _queue._unsafePull();
      }
    }

    return null;
  }

  void _handle(E event) {
    _currentProcess = _ConveyorProcess(
      event: event,
      onData: (state) {
        print('* process change state: $event $state');
        _setState(state);
      },
      onCancel: (reason, stackTrace) {
        print('* process cancelled: $event $reason');
        _currentProcess = null;
        onCancel(event, reason, stackTrace);
        _run();
      },
      onError: (error, stackTrace) {
        print('* process failed: $event $error');
        _currentProcess = null;
        onError(event, error, stackTrace);
        _run();
      },
      onDone: () {
        print('* process completed: $event');
        _currentProcess = null;
        _run();
      },
    );
  }

  // ConveyorEvent<S, E> createEvent<CS>(
  //   Stream<S> Function() callback, {
  //   String? label,
  //   bool Function(S)? checkInitialState,
  //   bool Function(S)? checkState,
  // }) =>
  //     ConveyorEvent(
  //       callback,
  //       label: label,
  //       checkInitialState: checkInitialState,
  //       checkState: checkState,
  //     );
}
