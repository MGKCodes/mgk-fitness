import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_auth/mgk_auth.dart';

/// The server, answering however a test needs, and remembering what it was
/// asked.
class _FakeApi implements EmailSignIn {
  AccountStatus status = AccountStatus.newAccount;
  EmailFailure? failing;
  bool createSignsIn = false;
  final List<String> calls = <String>[];
  String? replacedWith;

  Future<void> _maybeFail() async {
    if (failing case final EmailFailure f) throw EmailSignInException(f);
  }

  @override
  Duration get timeout => const Duration(seconds: 20);

  @override
  Future<AccountStatus> lookup(String email) async {
    calls.add('lookup $email');
    await _maybeFail();
    return status;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn $email');
    await _maybeFail();
  }

  @override
  Future<bool> createAccount({
    required String email,
    required String password,
  }) async {
    calls.add('create $email');
    await _maybeFail();
    return createSignsIn;
  }

  /// Whether a replacement password is written, when one is asked for.
  bool replacementWrites = true;

  @override
  Future<bool> confirm({
    required String email,
    required String code,
    String? replacePassword,
  }) async {
    calls.add('confirm $code');
    await _maybeFail();
    if (replacePassword == null) return true;
    if (!replacementWrites) return false;
    replacedWith = replacePassword;
    return true;
  }

  @override
  Future<void> resendCode(String email) async {
    calls.add('resend');
    await _maybeFail();
  }

  @override
  Future<void> sendPasswordEmail(String email) async {
    calls.add('password email $email');
    await _maybeFail();
  }
}

void main() {
  late _FakeApi api;
  late DateTime now;
  late EmailSignInFlow flow;

  setUp(() {
    api = _FakeApi();
    now = DateTime(2026, 10, 19, 9);
    flow = EmailSignInFlow(api: api, clock: () => now);
  });

  group('the address leads to its step', () {
    for (final (status, step) in <(AccountStatus, EmailStep)>[
      (AccountStatus.newAccount, EmailStep.create),
      (AccountStatus.unconfirmed, EmailStep.create),
      (AccountStatus.password, EmailStep.password),
      (AccountStatus.apple, EmailStep.provider),
      (AccountStatus.google, EmailStep.provider),
    ]) {
      test('${status.name} goes to ${step.name}', () async {
        api.status = status;
        await flow.submitAddress(' you@example.com ');
        expect(flow.step, step);
        expect(flow.status, status);
        expect(flow.email, 'you@example.com');
      });
    }

    test(
      'something that is not an address is refused without asking',
      () async {
        await flow.submitAddress('you@example');
        expect(flow.step, EmailStep.address);
        expect(flow.error, isNotNull);
        expect(api.calls, isEmpty);
      },
    );

    test('a failed lookup stays put and says no connection', () async {
      api.failing = EmailFailure.unavailable;
      await flow.submitAddress('you@example.com');
      expect(flow.step, EmailStep.address);
      expect(flow.error, startsWith('No connection'));
      expect(flow.busy, isFalse);
    });
  });

  group('welcome back', () {
    setUp(() async {
      api.status = AccountStatus.password;
      await flow.submitAddress('you@example.com');
    });

    test('the right password signs in', () async {
      expect(await flow.signIn('secret'), isTrue);
      expect(flow.error, isNull);
    });

    test('a wrong password is called a wrong password', () async {
      api.failing = EmailFailure.wrongPassword;
      expect(await flow.signIn('nope'), isFalse);
      expect(flow.error, startsWith('Wrong password'));
      expect(flow.step, EmailStep.password);
    });

    test('an empty password is not sent', () async {
      expect(await flow.signIn(''), isFalse);
      expect(api.calls, <String>['lookup you@example.com']);
    });

    test('a forgotten password is sent to the address already typed', () async {
      await flow.forgotPassword();
      expect(api.calls.last, 'password email you@example.com');
      expect(flow.notice, contains('you@example.com'));
      expect(flow.error, isNull);
    });
  });

  group('a new account', () {
    setUp(() async {
      api.status = AccountStatus.newAccount;
      await flow.submitAddress('you@example.com');
    });

    test('a password that misses the rule is not sent', () async {
      expect(await flow.createAccount('password'), isFalse);
      expect(flow.error, contains('8 characters'));
      expect(api.calls.last, 'lookup you@example.com');
    });

    test('is made, and the code is waited for', () async {
      expect(await flow.createAccount('Password1!'), isFalse);
      expect(flow.step, EmailStep.code);
      expect(flow.canResend, isFalse);
      expect(flow.resendAt, now.add(const Duration(seconds: 60)));
    });

    test('signs straight in where confirmation is off', () async {
      api.createSignsIn = true;
      expect(await flow.createAccount('Password1!'), isTrue);
      expect(flow.step, EmailStep.create);
    });

    test(
      'the code signs it in, writing no password over a new account',
      () async {
        await flow.createAccount('Password1!');
        expect(await flow.confirm(' 123 456 '), isTrue);
        expect(api.calls.last, 'confirm 123456');
        expect(api.replacedWith, isNull);
      },
    );

    test('a code that is not 6 digits is not sent', () async {
      await flow.createAccount('Password1!');
      expect(await flow.confirm('12345'), isFalse);
      expect(api.calls.last, 'create you@example.com');
    });

    test('a refused code says so, and stays on the code', () async {
      await flow.createAccount('Password1!');
      api.failing = EmailFailure.codeRefused;
      expect(await flow.confirm('000000'), isFalse);
      expect(flow.error, contains('wrong or has expired'));
      expect(flow.step, EmailStep.code);
    });

    test('a new code waits its minute', () async {
      await flow.createAccount('Password1!');
      await flow.resend();
      expect(api.calls.last, 'create you@example.com', reason: 'too soon');

      now = now.add(const Duration(seconds: 61));
      expect(flow.canResend, isTrue);
      await flow.resend();
      expect(api.calls.last, 'resend');
      expect(flow.notice, contains('new code'));
      expect(flow.canResend, isFalse, reason: 'the minute starts again');
    });
  });

  test(
    'an unconfirmed address gets the new password, after the code',
    () async {
      api.status = AccountStatus.unconfirmed;
      await flow.submitAddress('you@example.com');
      await flow.createAccount('Newer1!pass');
      expect(await flow.confirm('123456'), isTrue);
      expect(api.replacedWith, 'Newer1!pass');
    },
  );

  test(
    'a replacement that fails still signs in, and says the first password works',
    () async {
      api.status = AccountStatus.unconfirmed;
      api.replacementWrites = false;
      await flow.submitAddress('you@example.com');
      await flow.createAccount('Newer1!pass');
      expect(await flow.confirm('123456'), isTrue);
      expect(flow.firstPasswordKept, isTrue);
      expect(flow.error, isNull);
    },
  );

  test('an Apple account can be given a password instead', () async {
    api.status = AccountStatus.apple;
    await flow.submitAddress('you@example.com');
    await flow.setPasswordInstead();
    expect(api.calls.last, 'password email you@example.com');
    expect(flow.notice, contains('set a password'));
  });

  test('Change goes back to the address and forgets the rest', () async {
    api.status = AccountStatus.unconfirmed;
    await flow.submitAddress('you@example.com');
    await flow.createAccount('Newer1!pass');
    flow.changeAddress();
    expect(flow.step, EmailStep.address);
    expect(flow.status, isNull);
    expect(flow.resendAt, isNull);

    // Coming back as a new address must not carry the held password.
    api.status = AccountStatus.newAccount;
    await flow.submitAddress('other@example.com');
    await flow.createAccount('Password1!');
    await flow.confirm('123456');
    expect(api.replacedWith, isNull);
  });

  test('a second request while one runs is ignored', () async {
    api.status = AccountStatus.password;
    await flow.submitAddress('you@example.com');
    final first = flow.signIn('secret');
    expect(flow.busy, isTrue);
    expect(await flow.signIn('secret'), isFalse);
    expect(await first, isTrue);
    expect(api.calls.where((c) => c.startsWith('signIn')), hasLength(1));
  });

  test('a request that outlives its screen finishes quietly', () async {
    final gate = Completer<void>();
    final slow = _SlowApi(gate.future);
    final flow = EmailSignInFlow(api: slow);
    final lookup = flow.submitAddress('you@example.com');
    flow.dispose();
    gate.complete();
    await expectLater(lookup, completes);
  });

  test('suggestions come from the shared rule', () {
    expect(flow.suggestionFor('you@gmial.com'), 'you@gmail.com');
  });
}

/// A server that answers the lookup only when told to.
class _SlowApi extends _FakeApi {
  _SlowApi(this._answer);

  final Future<void> _answer;

  @override
  Future<AccountStatus> lookup(String email) async {
    await _answer;
    return AccountStatus.password;
  }
}
