part of '../conveyor.dart';

/// Класс, сигнализирующий об отмене обработчика события.
@immutable
sealed class Cancelled {
  const Cancelled._();

  @override
  bool operator ==(covariant Cancelled other) =>
      identical(this, other) || runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Отменено выбрасыванием исключения.
///
/// Позволяем пользователю вручную отменять функцию-обработчик, вызывая
/// исключение внутри обработчика:
///
/// ```
/// throw CancelledByException();
/// ```
///
/// Прямой доступ к созданию других классов пользователь не имеет.
final class CancelledByException extends Cancelled implements Exception {
  const CancelledByException() : super._();

  @override
  String toString() => '$CancelledByException()';
}

/// Отменено вручную.
///
/// Позволяем пользователю отменять текущий процесс обработки события.
///
/// ```
/// conveyor.currentProcess.cancel();
/// ```
final class CancelledManually extends Cancelled {
  const CancelledManually._() : super._();

  @override
  String toString() => '$CancelledManually()';
}

/// Состояние не удовлетворяет условиям обработки события.
///
/// Причина срабатывает при изменении состояния извне во время обработки
/// события, если в событии заданы ограничения на допустимое состояние.
/// В этом случае сразу происходит отмена подписки на функцию-обработчик
/// события. Но реальное прекращение работы функции произойдёт только на
/// yield/yield*, либо на ручной проверке с помощью [ConveyorStateProvider].
///
/// В последнем случае причиной отмены останется
/// [CancelledByEventRulesOnExternalChange], а не [CancelledByCheckState].
final class CancelledByEventRulesOnExternalChange extends Cancelled {
  const CancelledByEventRulesOnExternalChange._() : super._();

  @override
  String toString() => '$CancelledByEventRulesOnExternalChange()';
}

/// Удалено из очереди, потому что состояние не удовлетворяет условиям
/// обработки события.
///
/// Причина срабатывает при поиске очередного события для обработки.
final class RemovedFromQueueByEventRules extends Cancelled {
  const RemovedFromQueueByEventRules._() : super._();

  @override
  String toString() => '$RemovedFromQueueByEventRules()';
}

/// Состояние не удовлетворяет условию работы в текущем месте
/// функции-обработчика.
///
/// Причина срабатывает при ручной проверке с помощью [ConveyorStateProvider].
final class CancelledByCheckState extends Cancelled implements Exception {
  final String? description;

  const CancelledByCheckState._([this.description]) : super._();

  @override
  String toString() => '$CancelledByCheckState(${description ?? ''})';
}

/// Событие удалено из очереди вручную.
///
/// ```
/// conveyor.remove(...);
/// ```
final class RemovedFromQueueManually extends Cancelled {
  const RemovedFromQueueManually._() : super._();

  @override
  String toString() => '$RemovedFromQueueManually()';
}
