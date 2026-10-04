import 'dart:async';

/// Serializes player work and closes admission before native disposal starts.
class PlayerOperationQueue {
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposal;
  bool _closed = false;

  Future<void> run(
    Future<void> Function() operation, {
    bool Function()? isCurrent,
  }) {
    if (_closed) return Future<void>.value();
    final result = _tail.then((_) async {
      if (_closed || (isCurrent != null && !isCurrent())) return;
      await operation();
    });
    // A failed operation must not prevent cleanup or the next operation.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> close(Future<void> Function() dispose) {
    _closed = true;
    return _disposal ??= _tail.then((_) => dispose());
  }
}
