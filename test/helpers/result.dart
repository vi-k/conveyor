import 'package:conveyor/conveyor.dart';

extension ConveyorResultExt on ConveyorResult {
  void saveToResults(
    String name,
    List<(String, ConveyorResult)> results,
  ) {
    results.add((name, this));
  }
}
