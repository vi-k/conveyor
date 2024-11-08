part of 'conveyor.dart';

final class ConveyorQueue<BaseState extends Object,
        Event extends ConveyorEvent<BaseState, Event, BaseState>>
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
  Event insert(
    // ignore: avoid_renaming_method_parameters
    Event event, {
    Event? before,
    Event? after,
  }) {
    debug(
      'insert $event'
      '${before == null ? '' : ' before $before'}'
      '${after == null ? '' : ' after $after'}',
    );

    final isEmpty = this.isEmpty;
    super.insert(event, before: before, after: after);
    if (isEmpty) {
      onResume?.call();
    }

    return event;
  }

  @override
  // ignore: avoid_renaming_method_parameters
  void remove(Event event) {
    if (event.unkilled) {
      debug("remove $event - can't be removed");
      return;
    }

    debug('remove $event');

    super.remove(event);
    if (isEmpty) {
      onPause?.call();
    }

    event._result.cancel(
      const RemovedManually._(),
      StackTrace.current,
    );
    onRemove?.call(event);
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
