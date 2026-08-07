import 'dart:async';

import '../domain/account.dart';

/// An in-memory account, for tests and the preview harness.
///
/// Here rather than under `test/` because the preview binary uses it too, and a
/// second near-identical fake is how two versions of "what signing in does"
/// start disagreeing.
class FakeAuth implements AuthService {
  FakeAuth({Account? account, this.failWith}) : _account = account;

  Account? _account;
  final _controller = StreamController<Account?>.broadcast();

  /// Makes every call throw. For driving the error states without a server.
  final AuthFailure? failWith;

  @override
  Account? get current => _account;

  @override
  Stream<Account?> get changes => _controller.stream;

  @override
  Future<Account> signIn({
    required String email,
    required String password,
  }) async => _finish(email);

  @override
  Future<Account> signUp({
    required String email,
    required String password,
  }) async => _finish(email);

  Account _finish(String email) {
    final failure = failWith;
    if (failure != null) throw AuthException(failure);
    final account = Account(id: 'fake-user', email: email.trim());
    _account = account;
    _controller.add(account);
    return account;
  }

  @override
  Future<void> signOut() async {
    _account = null;
    _controller.add(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  void dispose() => _controller.close();
}
