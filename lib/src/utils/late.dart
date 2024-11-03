final class Late<T extends Object?> {
  T? _value;
  bool _isInitialized = false;

  Late(T value)
      : _value = value,
        _isInitialized = true;

  Late.unitialized();

  bool get isInitialized => _isInitialized;

  bool get isNotInitialized => !_isInitialized;

  T? get valueOrNull => _isInitialized ? _value as T : null;

  T get value => _isInitialized
      ? _value as T
      : (throw StateError('Value is not initialized'));

  set value(T value) {
    _value = value;
    _isInitialized = true;
  }

  @override
  String toString() => 'Late${_isInitialized ? '($_value)' : '.unitialized()'}';
}

extension LateExt<T extends Object?> on T {
  Late<T> toLate() => Late<T>(this);
}
