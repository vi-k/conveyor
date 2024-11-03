part of 'conveyor.dart';

abstract interface class ConveyorResult {
  Future<void> get future;

  bool get isFinished;

  bool get isSuccess;

  bool get isError;

  bool get isCancelled;

  Object get error;

  Cancelled get cancellationReason;

  StackTrace get stackTrace;
}

final class _ConveyorResult implements ConveyorResult {
  (Object, StackTrace)? _finisher;

  final _futureCompleter = Completer<void>();

  _ConveyorResult();

  @override
  Future<void> get future => _futureCompleter.future;

  @override
  bool get isFinished => _futureCompleter.isCompleted;

  @override
  bool get isSuccess => _futureCompleter.isCompleted && _finisher == null;

  @override
  bool get isError {
    final finisher = _finisher;
    return finisher != null && finisher.$1 is! Cancelled;
  }

  @override
  bool get isCancelled {
    final finisher = _finisher;
    return finisher != null && finisher.$1 is Cancelled;
  }

  @override
  Object get error {
    final finisher = _finisher?.$1;
    if (finisher != null && finisher is! Cancelled) {
      return finisher;
    }

    throw StateError('No error');
  }

  @override
  Cancelled get cancellationReason {
    final finisher = _finisher?.$1;
    if (finisher is Cancelled) {
      return finisher;
    }

    throw StateError('Not cancelled');
  }

  @override
  StackTrace get stackTrace {
    final stackTrace = _finisher?.$2;
    if (stackTrace != null) {
      return stackTrace;
    }

    throw StateError('No stacktrace');
  }

  void complete() {
    _checkResult();
    _finisher = null;
    _futureCompleter.complete();
  }

  void completeError(Object error, StackTrace stackTrace) {
    _checkResult();
    _finisher = (error, stackTrace);
    _futureCompleter.complete();
  }

  void cancel(Cancelled reason, StackTrace stackTrace) {
    _checkResult();
    _finisher = (reason, stackTrace);
    _futureCompleter.complete();
  }

  void _checkResult() {
    if (_futureCompleter.isCompleted) {
      throw StateError(
        _finisher!.$1 is Cancelled ? 'Already cancelled' : 'Already completed',
      );
    }
  }

  @override
  String toString() => !isFinished
      ? 'not completed'
      : isCancelled
          ? cancellationReason.toString()
          : isError
              ? error.toString()
              : 'completed';
}
