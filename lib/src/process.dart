part of 'conveyor.dart';

abstract interface class ConveyorProcess<S extends Object,
    E extends ConveyorEvent<S, E>> {
  E get event;

  bool get inProgress;

  Future<void> get future;

  Future<void> cancel();

  void forceCancel();
}

class _ConveyorProcess<S extends Object, E extends ConveyorEvent<S, E>>
    implements ConveyorProcess<S, E> {
  @override
  final E event;

  final void Function(S state) onData;

  final void Function(Object error, StackTrace stackTrace) onError;

  final void Function(Cancelled reason, StackTrace stackTrace) onCancel;

  final void Function() onDone;

  StreamSubscription<S>? _subscription;

  _ConveyorProcess({
    required this.event,
    required this.onData,
    required this.onError,
    required this.onCancel,
    required this.onDone,
  }) {
    print('* process start: $event');

    _subscription = event.callback().listen(
      onData,
      // ignore: avoid_types_on_closure_parameters
      onError: (Object error, StackTrace stackTrace) async {
        await _subscription?.cancel();
        _subscription = null;
        if (error is Cancelled) {
          event._result._cancel(error, stackTrace);
          onCancel(error, stackTrace);
        } else {
          event._result.completeError(error, stackTrace);
          onError(error, stackTrace);
        }
      },
      onDone: () {
        _subscription = null;
        event._result.complete();
        onDone();
      },
      cancelOnError: true,
    );
  }

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

  Future<void> _cancel(
    Cancelled reason, {
    bool forceCancel = false,
  }) async {
    final subscription = _subscription;
    if (subscription != null) {
      final future = subscription.cancel().onError<Object>((error, stackTrace) {
        if (error is! Cancelled) {
          Error.throwWithStackTrace(error, stackTrace);
        }
      });

      if (!forceCancel) {
        await future;
      }

      _subscription = null;
      final stackTrace = StackTrace.current;
      event._result._cancel(reason, stackTrace);
      onCancel(reason, stackTrace);
    }
  }
}
