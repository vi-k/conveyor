part of 'conveyor.dart';

/// Событие конвейера.
abstract base class ConveyorEvent<
    BaseState extends Object,
    Event extends ConveyorEvent<BaseState, Event, BaseState>,
    WorkingState extends BaseState> extends LinkedListItem<Event> {
  /// Событие конвейера с переданной функцией его обработки [_process].
  ///
  /// Требуемые типы:
  /// - [BaseState] и [Event] - состояние и события, с которыми работает
  ///   конвейер.
  /// - [WorkingState] - допустимое рабочее состояние (и входящее,
  ///   и промежуточное, и исходящее).
  ///
  /// Пример:
  ///
  /// ```dart
  /// final event = MyEvent<MyState, MyEvent, MyWorkingState, MyResultState>(
  ///   ...
  /// );
  /// ```
  ///
  /// Конвейер работает с состоянием `MyState`, являющейся основой для всех
  /// возможных состояний конвейера, но данное событие работает только
  /// с состоянием `MyWorkingState`, а возвращает `MyResultState`.
  ///
  /// Дополнительно могут быть заданы калбэки, проверящие состояние на разных
  /// этапах:
  ///
  /// - [checkStateBeforeProcessing] проверяет состояние перед началом
  ///   обработки. Если подошла очередь выполнения события, а тип текущего
  ///   состояния не соответствует [WorkingState] или проверка
  ///   [checkStateBeforeProcessing] вернула `false`, событие удаляется из
  ///   очереди с признаком [RemovedFromQueueByEventRules].
  ///
  ///   Пример:
  ///
  ///   ```dart
  ///   final event = MyEvent<MyState, MyEvent, MyWorkingState, MyResultState>(
  ///     checkStateBeforeProcessing: (state) => state.param == 42,
  ///     ...
  ///   );
  ///   ```
  ///
  ///   Событие может начать работу только из состояния MyWorkingState,
  ///   параметр `param` в котором равен 42.
  ///
  /// - [checkStateOnExternalChange] проверяет состояние при его изменении
  ///   извне (если такое изменение допускается в вашем конвейере). Если
  ///   состояние изменилось и тип состояния не соответствует [WorkingState]
  ///   или проверка [checkStateOnExternalChange] вернула `false`, обработка
  ///   события прерывается с признаком [CancelledByEventRules].
  ///
  ///   Пример 1:
  ///
  ///   ```dart
  ///   final event = MyEvent<MyState, MyEvent, MyWorkingState, MyResultState>(
  ///     checkStateOnExternalChange: (state) => state.param == 42,
  ///     ...
  ///   );
  ///   ```
  ///
  ///   Событие позволяет менять состояние извне, но только при сохранении
  ///   типа `MyWorkingState`, с которым работает событие. Параметр `param`
  ///   в этом состоянии должен быть равен 42.
  ///
  ///   Пример 2:
  ///
  ///   ```dart
  ///   final event = MyEvent<MyState, MyEvent, MyWorkingState, MyResultState>(
  ///     checkStateOnExternalChange: (state) => false,
  ///     ...
  ///   );
  ///   ```
  ///
  ///   Событие не позволяет менять состояние извне ни при каких
  ///   обстоятельствах. При любом изменении обработка события будет
  ///   прервана.
  ///
  /// - [checkState] - общая проверка. Используется во время обработки события
  ///   в провайдере состояния `state`, переданном внутрь обработчика
  ///   [_process], а также вместо [checkStateBeforeProcessing] и
  ///   [checkStateOnExternalChange], если они не заданы.
  ///
  ///   Пример 1:
  ///
  ///   ```dart
  ///   final event = MyEvent<MyState, MyEvent, MyWorkingState, MyResultState>(
  ///     checkState: (state) => state.param == 42,
  ///     (state) async* {
  ///       yield state.value.copyWith(param: 128);
  ///
  ///       await ...
  ///
  ///       state.value;
  ///     }
  ///     ...
  ///   );
  ///   ```
  ///
  ///   Рабочее состояние события: `MyWorkingState`. Тип будет проверяться
  ///   на каждом этапе проверок. Но помимо этого на всех этапах будет
  ///   проверяться и параметр `param` у состояния `MyWorkingState`:
  ///   и перед стартом события, и при внешних изменениях, и при внутренней
  ///   проверке с помощью провайдера состояни `state`. При этом внутри
  ///   обработчика мы можем изменить параметр `param` и это не приведёт
  ///   к прерыванию события. Отмена произойдёт на второй проверке `state`,
  ///   если к этому моменту во время `await` внешний источник не вернёт
  ///   параметру `param` значение 42.
  ///
  ///   Пример 2:
  ///
  ///   ```dart
  ///   final event = CameraEvent<CameraState, CameraEvent, CameraReadyState,
  ///       CameraReadyState>(
  ///     checkStateBeforeProcessing: (state) => state.focusPointSupported
  ///         && state.exposurePointSupported,
  ///     checkState: (state) => state.param == 42,
  ///     (state) async* {
  ///       try {
  ///         // внешний процесс, меняющий состояние
  ///         await setFocusPoint(point);
  ///         // проверяем, сделал ли он то, что ждём
  ///         state.test((it) => it.focusPoint == point);
  ///
  ///         await setExposurePoint(point);
  ///         state.test((it) => it.exposurePoint == point);
  ///
  ///         yield ...
  ///       } on Cancelled {
  ///         await setAutoFocus();
  ///         rethrow;
  ///       }
  ///     }
  ///   );
  ///   ```
  ///
  ///   Установка точки в видоискателе камеры, по которой будет настраиваться
  ///   фокус и экспозиция камеры. В начале проверяется готовность камеры
  ///   к работе (состояние `CameraReadyState`) и поддержка камерой установки
  ///   точек экспозиции и фокусировки. В ином случае событие будет удалено
  ///   из очереди, не запустившись. Параметр `param` проверяться перед
  ///   стартом не будет: задан калбэк `checkStateBeforeProcessing`, поэтому
  ///   проверка в `checkState` на этом этапе будет опущена. Но при вызовах
  ///   внутреннего калбэка `checkState` во время обработки события `param`
  ///   будет проверяться наряду с `focusPoint` и `exposurePoint`. При любой
  ///   неудачной проверке работа события будет прервана и вызван блок
  ///   `on Cancelled`.
  ConveyorEvent(
    this._process, {
    this.key,
    bool Function(WorkingState state)? checkStateBeforeProcessing,
    bool Function(WorkingState state)? checkStateOnExternalChange,
    bool Function(WorkingState state)? checkState,
    String Function()? debugInfo,
  })  : _checkStateBeforeProcessing = checkStateBeforeProcessing,
        _checkStateOnExternalChange = checkStateOnExternalChange,
        _checkState = checkState,
        _debugInfo = debugInfo,
        _result = _ConveyorResult() {
    assert(this is Event, 'The event type must be $Event');

    final classType = '$runtimeType';
    final genericTypeStart = classType.indexOf('<');
    _classType = genericTypeStart == -1
        ? classType
        : classType.substring(0, genericTypeStart);
  }

  final Stream<WorkingState> Function(
    RootConveyorStateProvider<BaseState, Event, WorkingState> state,
  ) _process;

  final Object? key;

  final bool Function(WorkingState state)? _checkStateBeforeProcessing;

  final bool Function(WorkingState state)? _checkStateOnExternalChange;

  final bool Function(WorkingState state)? _checkState;

  final String Function()? _debugInfo;

  final _ConveyorResult _result;

  late final String _classType;

  ConveyorResult get result => _result;

  /// Проверяет состояние перед запуском обработки события.
  void checkStateBeforeProcessing(BaseState state) {
    if (state is! WorkingState) {
      throw RemovedFromQueueByEventRules._('is not $WorkingState');
    }

    final checkStateBeforeProcessing = _checkStateBeforeProcessing;
    if (checkStateBeforeProcessing != null &&
        !checkStateBeforeProcessing(state)) {
      throw const RemovedFromQueueByEventRules._('checkStateBeforeProcessing');
    }

    final checkState = _checkState;
    if (checkState != null && !checkState(state)) {
      throw const RemovedFromQueueByEventRules._('checkState');
    }
  }

  /// Проверяет состояние при внешнем изменении.
  void checkStateOnExternalChange(BaseState state) {
    if (state is! WorkingState) {
      throw CancelledByEventRules._('is not $WorkingState');
    }

    final checkStateOnExternalChange = _checkStateOnExternalChange;
    if (checkStateOnExternalChange != null &&
        !checkStateOnExternalChange(state)) {
      throw const CancelledByEventRules._('checkStateOnExternalChange');
    }

    final checkState = _checkState;
    if (checkState != null && !checkState(state)) {
      throw const CancelledByEventRules._('checkState');
    }
  }

  /// Запуск обработки события.
  ///
  /// В калбэк обработки события для проверки и возврата состояния передаётся
  /// провайдер состояния [ConveyorStateProvider] для доступа к состоянию
  /// конвейера.
  (RootConveyorStateProvider<BaseState, Event, BaseState>, Stream<WorkingState>)
      _run(
    Conveyor<BaseState, Event> conveyor,
    ConveyorProcess<BaseState, Event> process,
  ) {
    final stateProvider =
        RootConveyorStateProvider<BaseState, Event, WorkingState>(
      conveyor,
      process,
      _checkState,
    );

    return (stateProvider, _process(stateProvider));
  }

  String debugInfo() => _debugInfo?.call() ?? '';

  @override
  String toString() => '$_classType(${key == null ? '' : '$key'})';
}
