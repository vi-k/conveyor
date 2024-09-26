// import 'dart:async';

// import 'event.dart';
// import 'process.dart';
// import 'queue.dart';
// import 'result.dart';

// abstract class Conveyor<_State extends Object,
//     _Event extends ConveyorEvent<_State>> {
//   final _queue = $ConveyorQueue<_State, _Event>();
//   final _stateController = StreamController<_State>.broadcast();

//   _State _state;
//   $ConveyorProcess<_State, _Event, $ConveyorResult>? _currentProcess;

//   Conveyor(
//     _State initialState,
//   ) : _state = initialState;

//   ConveyorQueue<_State, _Event, ConveyorItem<_State, _Event, ConveyorResult>>
//       get queue => _queue;

//   _State get state => _state;

//   Stream get stream => _stateController.stream;

//   ConveyorProcess<_State, _Event, ConveyorResult>? get currentProcess =>
//       _currentProcess;

//   bool get inProgress => _currentProcess != null;

//   Future<void> close() async {
//     _queue.clear();
//     // При закрытии дожидаемся окончания текущего рабочего процесса.
//     await cancelCurrentProccess(
//       awaitCompletion: true,
//     );
//     await _stateController.close();
//   }

//   Future<bool> cancelCurrentProccess({
//     bool awaitCompletion = true,
//   }) async {
//     final currentProcess = _currentProcess;
//     if (currentProcess == null) {
//       return true;
//     }

//     final cancelled = await currentProcess.cancel(
//       awaitCompletion: awaitCompletion,
//     );

//     if (cancelled) {
//       _currentProcess = null;
//       run();
//     }

//     return cancelled;
//   }

//   Future<void> awaitCurrentProccess() async {
//     final currentProcess = _currentProcess;
//     if (currentProcess != null) {
//       await currentProcess.awaitCompletion();
//     }
//   }

//   void run() async {
//     if (_currentProcess != null) {
//       return;
//     }

//     final item = _pull();
//     if (item != null) {
//       _handle(item.event, item.result);
//     }
//   }

//   FutureOr<void> onError(
//     _Event event,
//     Object error,
//     StackTrace stackTrace,
//   ) {
//     print('$error\n$stackTrace');
//     run();
//   }

//   ConveyorItem<_State, _Event, $ConveyorResult>? _pull() {
//     for (final item in _queue) {
//       final readyForProcessing = item.event.readyForProcessing;
//       if (readyForProcessing == null || readyForProcessing(_state)) {
//         item.unlink();
//         return item;
//       }
//     }

//     return null;
//   }

//   void _handle(_Event event, $ConveyorResult result) {
//     _currentProcess = $ConveyorProcess(
//       event: event,
//       result: result,
//       onData: (state) {
//         _state = state;
//         _stateController.add(state);
//       },
//       onError: (error, stackTrace) {
//         _currentProcess = null;
//         onError(event, error, stackTrace);
//       },
//       onDone: () {
//         _currentProcess = null;
//         run();
//       },
//     );
//   }
// }
