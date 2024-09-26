import 'dart:async';

import 'package:conveyor/conveyor.dart';

import 'event.dart';
import 'state.dart';

final class TestConveyor extends Conveyor<MyState, MyEvent>
    with SetState<MyState, MyEvent> {
  TestConveyor(super.initialState);

  void externalSetState(MyState state) => setState(state);

  ConveyorResult init() {
    final event = MyEvent(
      label: 'init',
      checkInitialState: (state) => state is Initial,
      // Отменяем при любом внешнем изменении состояния.
      checkState: (state) => false,
      () async* {
        print('** init start');
        try {
          yield const InProgress();
          await Future<void>.delayed(const Duration(milliseconds: 100));

          yield state<InProgress>().copyWith(progress: 50);
          await Future<void>.delayed(const Duration(milliseconds: 100));

          yield state<InProgress>().copyWith(progress: 100);
          await Future<void>.delayed(const Duration(milliseconds: 100));

          checkState<InProgress>((state) => state.progress == 100);
          yield const Ready(a: 0, b: 0);
        } finally {
          print('** init finally');
        }
      },
    );

    queue.push(event);

    return event.result;
  }

  ConveyorResult incrementA() {
    final event = MyEvent(
      label: 'incrementA',
      checkState: (state) => state is Ready,
      () async* {
        print('** incrementA start');
        try {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final state = this.state<Ready>();
          yield state.copyWith(a: state.a + 1);
        } finally {
          print('** incrementA finally');
        }
      },
    );

    queue.push(event);

    return event.result;
  }

  ConveyorResult incrementB() {
    final event = MyEvent(
      label: 'incrementB',
      checkState: (state) => state is Ready,
      () async* {
        print('** incrementB start');
        try {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final state = this.state<Ready>();
          yield state.copyWith(b: state.b + 1);
        } finally {
          print('** incrementB finally');
        }
      },
    );

    queue.push(event);

    return event.result;
  }

  ConveyorResult finish() {
    final event = MyEvent(
      label: 'finish',
      checkState: (state) => state is! Disposed,
      () async* {
        print('** finish start');
        try {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          yield const Disposed();
        } finally {
          print('** finish finally');
        }
      },
    );

    queue.push(event);

    return event.result;
  }

  ConveyorResult extremalTest() {
    final event = MyEvent(
      label: 'extremalTest',
      () async* {
        print('** extremalTest start');
        try {
          externalSetState(const Ready(a: 0, b: 0));
          scheduleMicrotask(() {
            print('* microtask');
            externalSetState(const Ready(a: 2, b: 2));
          });
          yield state<Ready>().copyWith(a: 1, b: 1);
        } finally {
          print('** extremalTest finally');
        }
      },
    );

    queue.push(event);

    return event.result;
  }
}
