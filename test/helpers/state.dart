import 'package:meta/meta.dart';

@immutable
sealed class MyState {
  const MyState();
}

final class Initial extends MyState {
  const Initial();

  @override
  bool operator ==(covariant MyState other) => other is Initial;

  @override
  int get hashCode => (Initial).hashCode;

  @override
  String toString() => '$Initial()';
}

final class InProgress extends MyState {
  final int progress;

  const InProgress({
    this.progress = 0,
  });

  InProgress copyWith({
    int? progress,
  }) =>
      InProgress(
        progress: progress ?? this.progress,
      );

  @override
  bool operator ==(covariant MyState other) =>
      other is InProgress && progress == other.progress;

  @override
  int get hashCode => progress.hashCode;

  @override
  String toString() => '$InProgress(progress: $progress)';
}

final class Ready extends MyState {
  final int a;
  final int b;

  const Ready({
    required this.a,
    required this.b,
  });

  Ready copyWith({
    int? a,
    int? b,
  }) =>
      Ready(
        a: a ?? this.a,
        b: b ?? this.b,
      );

  @override
  bool operator ==(covariant MyState other) =>
      other is Ready && a == other.a && b == other.b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => '$Ready(a: $a, b: $b)';
}

final class Disposed extends MyState {
  const Disposed();

  @override
  bool operator ==(covariant MyState other) => other is Disposed;

  @override
  int get hashCode => (Disposed).hashCode;

  @override
  String toString() => '$Disposed()';
}
