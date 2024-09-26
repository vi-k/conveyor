part of 'conveyor.dart';

class ConveyorEvent<S extends Object, E extends ConveyorEvent<S, E>> {
  final String? label;
  final Stream<S> Function() callback;
  final bool Function(S state)? checkInitialState;
  final bool Function(S state)? checkState;

  final _ConveyorResult _result = _ConveyorResult();

  _ConveyorItem<S, E>? _item;

  ConveyorEvent(
    this.callback, {
    this.label,
    this.checkInitialState,
    this.checkState,
  });

  ConveyorResult get result => _result;

  ConveyorEvent<S, E>? get next {
    final item = _item;
    if (item == null) {
      _throwIfUnlinked();
    }

    return item.next?.event;
  }

  ConveyorEvent<S, E>? get previous {
    final item = _item;
    if (item == null) {
      _throwIfUnlinked();
    }

    return item.previous?.event;
  }

  void removeFromQueue() {
    final item = _item;
    if (item == null) {
      _throwIfUnlinked();
    }

    item.event._result._cancel(
      const RemovedFromQueueManually._(),
      StackTrace.current,
    );
    item.unlink();
    _item = null;
  }

  void pushAfter(E event) {
    final item = _item;
    if (item == null) {
      _throwIfUnlinked();
    }

    final newItem = _ConveyorItem<S, E>(event);
    event._item = newItem;
    item.insertAfter(newItem);
  }

  void pushBefore(E event) {
    final item = _item;
    if (item == null) {
      _throwIfUnlinked();
    }

    final newItem = _ConveyorItem<S, E>(event);
    event._item = newItem;
    item.insertBefore(newItem);
  }

  Never _throwIfUnlinked() => throw StateError('Event not in queue');

  @override
  String toString() => label ?? super.toString();
}
