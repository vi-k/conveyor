part of 'conveyor.dart';

abstract interface class ConveyorProcess<BaseState extends Object,
    Event extends ConveyorEvent<BaseState, Event, BaseState, BaseState>> {
  /// Уровень процесса.
  ///
  /// 0 - корневой, запускается напрямую из конвейера.
  /// 1-n - процессы, запускаемые из других процессов.
  int get level;

  /// Корневой процесс.
  bool get isRoot;

  /// Процесс-потомок.
  bool get isChild;

  /// Обрабатываемое событие.
  Event get event;

  /// Запущен ли процесс.
  bool get inProgress;

  /// Возможность дождаться окончания процесса.
  Future<void> get future;

  /// Отмена процесса.
  ///
  /// Дожидается его реального завершения.
  Future<void> cancel();

  /// Отмена процесса.
  ///
  /// Не дожидается его завершения.
  void forceCancel();

  /// Проверка события, обрабатываемого процессом.
  ///
  /// Возвращает событие, если проверка прошла успешно, и `null`, если [test]
  /// вернул `false`.
  Event? checkEvent(bool Function(Event event) test);
}

class _ConveyorProcess<BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState, BaseState>>
    implements ConveyorProcess<BaseState, Event> {
  final Conveyor<BaseState, Event> conveyor;

  @override
  final int level;

  @override
  final Event event;

  final void Function(BaseState state) onData;

  final void Function() onFinish;

  StreamSubscription<BaseState>? _subscription;

  Future<void>? _cancelFuture;

  _ConveyorProcess({
    required this.conveyor,
    required this.event,
    required this.onData,
    required this.onFinish,
    this.level = 0,
  }) {
    debug('process $event started');
    conveyor.onStart(this);

    _subscription = event._run(conveyor, this).listen(
      onData,
      // ignore: avoid_types_on_closure_parameters
      onError: (Object error, StackTrace stackTrace) async {
        await _subscription?.cancel();
        _subscription = null;
        if (error is Cancelled) {
          event._result.cancel(error, stackTrace);
          debug('process $event cancelled: $error');
          conveyor.onCancel(this);
        } else {
          event._result.completeError(error, stackTrace);
          debug('process $event failed: $error');
          conveyor.onError(this, error, stackTrace);
        }
        onFinish();
      },
      onDone: () {
        _subscription = null;
        event._result.complete();
        debug('process $event done');
        conveyor.onDone(this);
        onFinish();
      },
      cancelOnError: true,
    );
  }

  @override
  bool get isRoot => level == 0;

  @override
  bool get isChild => level != 0;

  @override
  bool get inProgress => _subscription != null;

  @override
  Future<void> get future => event.result.future;

  @override
  Future<void> cancel() => _cancel(const CancelledManually._());

  @override
  Future<void> forceCancel() => _cancel(
        const CancelledManually._(),
        forceCancel: true,
      );

  @override
  Event? checkEvent(bool Function(Event event) test) =>
      test(event) ? event : null;

  Future<void> _cancel(
    Cancelled reason, {
    bool forceCancel = false,
  }) async {
    final cancelFuture = _cancelFuture;
    if (cancelFuture != null) {
      if (!forceCancel) {
        await cancelFuture;
      }

      return;
    }

    final subscription = _subscription;
    if (subscription == null) {
      return;
    }

    debug('process $event cancelled: $reason');
    final future = subscription.cancel().onError<Object>((error, stackTrace) {
      if (error is! Cancelled) {
        conveyor.onError(this, error, stackTrace);
      }
    });
    _cancelFuture = future;

    if (!forceCancel) {
      await future;
    }

    _subscription = null;
    _cancelFuture = null;
    event._result.cancel(reason, StackTrace.current);
    conveyor.onCancel(this);
    onFinish();
  }
}
