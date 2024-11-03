// ignore_for_file: use_to_and_as_if_applicable

part of 'conveyor.dart';

/// Общий интерфейс провайдера, предоставляющего доступ к состоянию конвейера.
abstract interface class ConveyorStateProvider<
    BaseState extends Object,
    Event extends ConveyorEvent<BaseState, Event, BaseState, BaseState>,
    OutState extends BaseState> {
  ConveyorProcess<BaseState, Event> get process;

  OutState get value;

  T use<T>(T Function(OutState it) callback);

  Stream<OutState> run(Event event);

  /// Проверяет состояние на заданное условие.
  ConveyorStateProvider<BaseState, Event, OutState> test(
    bool Function(OutState it) test,
  );

  ConveyorStateProvider<BaseState, Event, CastState>
      isA<CastState extends BaseState>();

  /// Заменяет состояние новым.
  ConveyorStateProvider<BaseState, Event, CastState>
      map<CastState extends BaseState>(
    CastState Function(OutState it) callback,
  );

  /// Заменяет состояние новым с сохранением типа.
  ConveyorStateProvider<BaseState, Event, OutState> strongMap(
    OutState Function(OutState it) callback,
  );
}

/// Основа для провайдеров.
abstract base class _BaseConveyorStateProvider<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState, BaseState>,
        OutState extends BaseState>
    implements ConveyorStateProvider<BaseState, Event, OutState> {
  Conveyor<BaseState, Event> get _conveyor;

  BaseState get _state;

  OutState _checkState(BaseState state) => state is OutState
      ? state
      : throw CancelledByCheckState._('is not $OutState');

  @override
  T use<T>(T Function(OutState it) callback) => callback(value);

  @override
  Stream<OutState> run(Event event) {
    late final _ConveyorProcess<BaseState, Event> childProcess;
    final streamController = StreamController<OutState>(
      sync: true,
      onCancel: () => childProcess.cancel(),
    );

    childProcess = _ConveyorProcess(
      conveyor: _conveyor,
      level: process.level + 1,
      event: event,
      onData: (state) {
        debug('child process $event sent state: $state');
        try {
          streamController.add(_checkState(state));
        } on Object catch (error, stackTrace) {
          streamController.addError(error, stackTrace);
        }
      },
      onFinish: () {
        final result = event.result;
        if (!result.isSuccess) {
          streamController.addError(
            result.isCancelled ? result.cancellationReason : result.error,
            result.stackTrace,
          );
        }

        streamController.close();
      },
    );

    return streamController.stream;
  }

  /// Проверяет состояние на заданное условие.
  @override
  ConveyorStateProvider<BaseState, Event, OutState> test(
    bool Function(OutState it) test,
  ) =>
      _TestMatcherConveyorStateTransformer(this, test);

  /// Проверяет тип состояния.
  @override
  ConveyorStateProvider<BaseState, Event, CastState>
      isA<CastState extends BaseState>() =>
          _TypeMatcherConveyorStateTransformer<BaseState, Event, OutState,
              CastState>(this);

  /// Заменяет состояние новым.
  @override
  ConveyorStateProvider<BaseState, Event, CastState>
      map<CastState extends BaseState>(
    CastState Function(OutState it) callback,
  ) =>
          _MapConveyorStateProvider(this, callback);

  /// Заменяет состояние новым с сохранением типа.
  @override
  ConveyorStateProvider<BaseState, Event, OutState> strongMap(
    OutState Function(OutState it) callback,
  ) =>
      _StrongMapConveyorStateProvider(this, callback);
}

/// Корневой провайдер, напрямую предоставляющий доступ к состоянию конвейера.
final class _RootConveyorStateProvider<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState, BaseState>,
        OutState extends BaseState>
    extends _BaseConveyorStateProvider<BaseState, Event, OutState> {
  @override
  final Conveyor<BaseState, Event> _conveyor;

  @override
  final ConveyorProcess<BaseState, Event> process;

  _RootConveyorStateProvider(this._conveyor, this.process);

  @override
  BaseState get _state => _conveyor._state;

  @override
  OutState get value => _checkState(_conveyor._state);
}

/// Основа для трансформеров.
abstract base class _BaseConveyorStateTransformer<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState, BaseState>,
        WorkingState extends BaseState,
        OutState extends BaseState>
    extends _BaseConveyorStateProvider<BaseState, Event, OutState> {
  final _BaseConveyorStateProvider<BaseState, Event, BaseState> _previous;

  _BaseConveyorStateTransformer(this._previous);

  @override
  Conveyor<BaseState, Event> get _conveyor => _previous._conveyor;

  @override
  ConveyorProcess<BaseState, Event> get process => _previous.process;

  @override
  BaseState get _state => _checkState(_previous._state);

  @override
  OutState get value => _checkState(_previous._state);
}

final class _TestMatcherConveyorStateTransformer<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState, BaseState>,
        InOutState extends BaseState>
    extends _BaseConveyorStateTransformer<BaseState, Event, InOutState,
        InOutState> {
  final bool Function(InOutState state) _test;

  _TestMatcherConveyorStateTransformer(super._previous, this._test);

  @override
  InOutState _checkState(BaseState state) => state is InOutState && _test(state)
      ? state
      : throw CancelledByCheckState._('is not $InOutState');
}

final class _TypeMatcherConveyorStateTransformer<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState, BaseState>,
        WorkingState extends BaseState,
        OutState extends BaseState>
    extends _BaseConveyorStateTransformer<BaseState, Event, WorkingState,
        OutState> {
  _TypeMatcherConveyorStateTransformer(super._previous);
}

final class _MapConveyorStateProvider<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState, BaseState>,
        WorkingState extends BaseState,
        OutState extends BaseState>
    extends _BaseConveyorStateTransformer<BaseState, Event, WorkingState,
        OutState> {
  final OutState Function(WorkingState state) _callback;

  _MapConveyorStateProvider(super._previous, this._callback);

  @override
  OutState _checkState(BaseState state) => state is WorkingState
      ? _callback(state)
      : throw CancelledByCheckState._('is not $WorkingState');
}

final class _StrongMapConveyorStateProvider<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState, BaseState>,
        InOutState extends BaseState>
    extends _BaseConveyorStateTransformer<BaseState, Event, InOutState,
        InOutState> {
  final InOutState Function(InOutState state) _callback;

  _StrongMapConveyorStateProvider(super._previous, this._callback);

  @override
  InOutState _checkState(BaseState state) => state is InOutState
      ? _callback(state)
      : throw CancelledByCheckState._('is not $InOutState');
}
