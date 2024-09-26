part of 'conveyor.dart';

mixin SetState<S extends Object, E extends ConveyorEvent<S, E>>
    on Conveyor<S, E> {
  @protected
  void setState(S state) => _externalSetState(state);
}
