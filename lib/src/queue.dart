part of 'conveyor.dart';

final class ConveyorQueue<BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState, BaseState>>
    extends LinkedList<Event> {
  final void Function()? onPause;
  final void Function()? onResume;
  final void Function(Event event)? onRemove;

  ConveyorQueue({
    this.onPause,
    this.onResume,
    this.onRemove,
  });

  @override
  Event insert(Event element, {Event? before, Event? after}) {
    debug(
      'insert $element'
      '${before == null ? '' : ' before $before'}'
      '${after == null ? '' : ' after $after'}',
    );

    final isEmpty = this.isEmpty;
    super.insert(element, before: before, after: after);
    if (isEmpty) {
      onResume?.call();
    }

    return element;
  }

  @override
  void remove(Event element) {
    debug('remove $element');

    super.remove(element);
    if (isEmpty) {
      onPause?.call();
    }

    element._result.cancel(
      const RemovedFromQueueManually._(),
      StackTrace.current,
    );
    onRemove?.call(element);
  }

  @override
  void clear() {
    forEach(remove);
  }

  /// Вынимает из очереди первый элемент, но не отменяет его.
  Event? _unsafePull() {
    final event = firstOrNull;
    if (event != null) {
      super.remove(event);
    }

    return event;
  }
}
