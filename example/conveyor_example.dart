// import 'dart:async';

// import 'package:conveyor/conveyor.dart';

// /// Работа с данными:
// /// - получение данных
// /// - изменение данных
// /// - параллельно данные могут меняться внешним источником (изменяться
// ///   и удалиться)
// ///
// /// - событие об изменении данных отменяет предыдущее такое же
// /// - удаление отменяет все

// sealed class EntityState {
//   const EntityState();
// }

// final class Initial extends EntityState {
//   const Initial();

//   @override
//   String toString() => '$Initial()';
// }

// enum PreparingStep {
//   start,
//   loading,
//   parsing,
//   finish;

//   const PreparingStep();
// }

// final class Preparing extends EntityState {
//   final PreparingStep step;

//   const Preparing([this.step = PreparingStep.start]);

//   Preparing copyWith({
//     PreparingStep? step,
//   }) =>
//       Preparing(step ?? this.step);

//   @override
//   String toString() => '$Preparing(step: $step)';
// }

// final class Working extends EntityState {
//   final int param1;
//   final int param2;

//   const Working({
//     this.param1 = 0,
//     this.param2 = 0,
//   });

//   Working copyWith({
//     int? param1,
//     int? param2,
//   }) =>
//       Working(
//         param1: param1 ?? this.param1,
//         param2: param2 ?? this.param2,
//       );

//   @override
//   String toString() => '$Working(a: $param1, b: $param2)';
// }

// final class Deleted extends EntityState {
//   const Deleted();

//   @override
//   String toString() => '$Deleted()';
// }

// final class EntityEvent<WorkingState extends EntityState> extends ConveyorEvent<
//     EntityState, EntityEvent<WorkingState>, WorkingState> {
//   EntityEvent(
//     super.process, {
//     super.uncancellable,
//     super.unkilled,
//     super.checkStateBeforeProcessing,
//     super.checkStateOnExternalChange,
//     super.checkState,
//     super.debugInfo,
//   });
// }

// final class EntityConveyor extends Conveyor<EntityState, EntityEvent>
//     with ExternalSetState<EntityState, EntityEvent> {
//   EntityConveyor(super.initialState);

//   // void init() {
//   //   final event =
//   // }
// }

// Future<void> main() async {}
