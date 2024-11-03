import 'package:conveyor/conveyor.dart';

import 'state.dart';

final class TestEvent<WorkingState extends TestState,
        OutState extends TestState>
    extends ConveyorEvent<TestState, TestEvent<TestState, TestState>,
        WorkingState, OutState> {
  TestEvent(
    super.callback, {
    required String super.key,
    super.checkStateBeforeProcessing,
    super.checkStateOnExternalChange,
    super.checkState,
    super.debugInfo,
  });

  @override
  String get key => super.key! as String;

  @override
  String toString() => '[$key]';
}
