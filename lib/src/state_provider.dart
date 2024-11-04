// ignore_for_file: use_to_and_as_if_applicable

part of 'conveyor.dart';

/// Общий интерфейс провайдера, предоставляющего доступ к состоянию конвейера.
abstract interface class ConveyorStateProvider<
    BaseState extends Object,
    Event extends ConveyorEvent<BaseState, Event, BaseState>,
    OutState extends BaseState> {
  ConveyorProcess<BaseState, Event> get process;

  OutState get value;

  T use<T>(T Function(OutState it) callback);

  void check();

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
}

/// Основа для провайдеров.
abstract base class _BaseConveyorStateProvider<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>,
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
        try {
          check();
        } on Object catch (error, stackTrace) {
          streamController.addError(error, stackTrace);
        }
        streamController.close();

        final currentProcesses = _conveyor._currentProcesses;
        if (currentProcesses != null) {
          currentProcesses.remove(childProcess);
        }
      },
    );

    final currentProcesses = _conveyor._currentProcesses;
    if (currentProcesses != null) {
      currentProcesses.add(childProcess);
    }

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
}

/// Корневой провайдер, напрямую предоставляющий доступ к состоянию конвейера.
final class RootConveyorStateProvider<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>,
        OutState extends BaseState>
    extends _BaseConveyorStateProvider<BaseState, Event, OutState> {
  @override
  final Conveyor<BaseState, Event> _conveyor;

  @override
  final ConveyorProcess<BaseState, Event> process;

  final bool Function(OutState)? _userCheckState;

  RootConveyorStateProvider(
    this._conveyor,
    this.process,
    this._userCheckState,
  );

  @override
  BaseState get _state => _conveyor._state;

  @override
  OutState _checkState(BaseState state) {
    if (state is! OutState) {
      throw CancelledByEventRules._('is not $OutState');
    }

    final userCheckState = _userCheckState;
    if (userCheckState != null && !userCheckState(state)) {
      throw const CancelledByEventRules._('checkState');
    }

    return state;
  }

  @override
  OutState get value => _checkState(_conveyor._state);

  @override
  void check() {
    _checkState(_conveyor._state);
  }

  void log(Object? message) {
    _conveyor.onRawLog(process, message);
  }
}

/// Основа для трансформеров.
abstract base class _BaseConveyorStateTransformer<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>,
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
  OutState get value => _checkState(_previous.value);

  @override
  void check() {
    _checkState(_previous.value);
  }
}

final class _TestMatcherConveyorStateTransformer<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>,
        WorkingState extends BaseState>
    extends _BaseConveyorStateTransformer<BaseState, Event, WorkingState,
        WorkingState> {
  final bool Function(WorkingState state) _test;

  _TestMatcherConveyorStateTransformer(super._previous, this._test);

  @override
  WorkingState _checkState(BaseState state) {
    if (state is! WorkingState) {
      throw CancelledByCheckState._('is not $WorkingState');
    }

    if (!_test(state)) {
      throw const CancelledByCheckState._('test');
    }

    return state;
  }
}

final class _TypeMatcherConveyorStateTransformer<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>,
        WorkingState extends BaseState,
        OutState extends BaseState>
    extends _BaseConveyorStateTransformer<BaseState, Event, WorkingState,
        OutState> {
  _TypeMatcherConveyorStateTransformer(super._previous);
}

final class _MapConveyorStateProvider<
        BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>,
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
