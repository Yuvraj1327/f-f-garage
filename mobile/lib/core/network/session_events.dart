import 'dart:async';

/// Lets the network layer announce "the session is no longer valid" without
/// depending on any feature code. The auth controller listens and signs out.
class SessionEvents {
  final StreamController<void> _expired = StreamController<void>.broadcast();

  Stream<void> get expired => _expired.stream;

  void notifyExpired() {
    if (!_expired.isClosed) {
      _expired.add(null);
    }
  }

  Future<void> dispose() => _expired.close();
}
