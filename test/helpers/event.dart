import 'package:conveyor/conveyor.dart';

import 'state.dart';

final class MyEvent extends ConveyorEvent<MyState, MyEvent> {
  MyEvent(
    super.callback, {
    super.label,
    super.checkInitialState,
    super.checkState,
  });
}
