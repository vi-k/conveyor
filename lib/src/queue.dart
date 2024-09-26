part of 'conveyor.dart';

final class _ConveyorItem<S extends Object, E extends ConveyorEvent<S, E>>
    extends LinkedListEntry<_ConveyorItem<S, E>> {
  final E event;

  _ConveyorItem(this.event);
}

final class ConveyorQueue<S extends Object, E extends ConveyorEvent<S, E>>
    extends Iterable<E> {
  final _list = LinkedList<_ConveyorItem<S, E>>();

  final void Function() onOccurrenceEvent;

  ConveyorQueue({
    required this.onOccurrenceEvent,
  });

  @override
  Iterator<E> get iterator => _ConveyorQueueIterator(this);

  /// Возвращает первое событие в очереди.
  @override
  E get first {
    if (_list.isEmpty) {
      throw StateError('No such event');
    }

    return _list.first.event;
  }

  /// Возвращает первое событие в очереди или `null`.
  E? get firstOrNull => _list.isEmpty ? null : _list.first.event;

  /// Возвращает последнее событие в очереди.
  @override
  E get last {
    if (_list.isEmpty) {
      throw StateError('No such event');
    }

    return _list.last.event;
  }

  /// Возвращает последнее событие в очереди или `null`.
  E? get lastOrNull => _list.isEmpty ? null : _list.last.event;

  /// Возвращает единственное событие в очереди, если оно единственное.
  @override
  E get single {
    if (_list.isEmpty) {
      throw StateError('No such event');
    }

    if (_list.length > 1) {
      throw StateError('Too many events');
    }

    return _list.first.event;
  }

  /// Возвращает единственное событие в очереди или `null`.
  E? get singleOrNull =>
      _list.isEmpty || _list.length > 1 ? null : _list.last.event;

  /// Возвращает длину очереди.
  @override
  int get length => _list.length;

  /// Возвращает, пуста ли очередь.
  @override
  bool get isEmpty => _list.isEmpty;

  /// Очищает очередь.
  void clear() {
    var item = _list.firstOrNull;
    while (item != null) {
      item.event.removeFromQueue();
      item = _list.firstOrNull;
    }
    _list.clear();
  }

  /// Проверяет, находится ли указанное событие в очереди.
  @override
  // ignore: avoid_renaming_method_parameters
  bool contains(covariant E event) => identical(this, event._item?.list);

  @override
  void forEach(void Function(E element) action) {
    for (final item in _list) {
      action(item.event);
    }
  }

  /// Добавляет событие в конец очереди.
  void push(E event) {
    final isEmpty = _list.isEmpty;

    final item = _ConveyorItem<S, E>(event);
    event._item = item;
    _list.add(item);

    if (isEmpty) {
      onOccurrenceEvent();
    }
  }

  /// Добавляет событие в начало очереди.
  void pushFirst(E event) {
    final isEmpty = _list.isEmpty;

    final item = _ConveyorItem<S, E>(event);
    event._item = item;
    _list.addFirst(item);

    if (isEmpty) {
      onOccurrenceEvent();
    }
  }

  /// Удаляет событие оз очереди.
  void remove(E event) => event.removeFromQueue();

  /// Вынимает из очереди первый элемент, но не отменяет его.
  _ConveyorItem<S, E>? _unsafePull() => _list.firstOrNull?..unlink();
}

class _ConveyorQueueIterator<S extends Object, E extends ConveyorEvent<S, E>>
    implements Iterator<E> {
  final Iterator<_ConveyorItem<S, E>> _iterator;

  _ConveyorQueueIterator(ConveyorQueue<S, E> queue)
      : _iterator = queue._list.iterator;

  @override
  E get current => _iterator.current.event;

  @override
  bool moveNext() => _iterator.moveNext();
}
