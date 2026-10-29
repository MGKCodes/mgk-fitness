import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// Every press, as a list of words a test can read.
class _Presses {
  final List<String> log = <String>[];
}

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: SingleChildScrollView(child: SizedBox(width: 360, child: child)),
  ),
);

EmailSignInSteps _steps(
  _Presses p, {
  EmailStage stage = EmailStage.address,
  String email = 'you@example.com',
  SignInProvider provider = SignInProvider.apple,
  bool busy = false,
  String? error,
  String? notice,
  DateTime? resendAt,
  DateTime Function()? clock,
  String? Function(String)? suggest,
  List<PasswordRequirement> Function(String)? requirements,
  VoidCallback? onOtherWays,
}) => EmailSignInSteps(
  stage: stage,
  email: email,
  provider: provider,
  busy: busy,
  error: error,
  notice: notice,
  resendAt: resendAt,
  clock: clock ?? DateTime.now,
  suggest: suggest,
  requirements: requirements,
  onOtherWays: onOtherWays,
  onAddress: (v) => p.log.add('address $v'),
  onPassword: (v) => p.log.add('password $v'),
  onForgotPassword: () => p.log.add('forgot'),
  onProvider: () => p.log.add('provider'),
  onSetPassword: () => p.log.add('set password'),
  onCreate: (v) => p.log.add('create $v'),
  onCode: (v) => p.log.add('code $v'),
  onResend: () => p.log.add('resend'),
  onChangeAddress: () => p.log.add('change'),
);

void main() {
  testWidgets('the address alone, then Continue', (tester) async {
    final p = _Presses();
    await tester.pumpWidget(_host(_steps(p, email: '')));

    await tester.enterText(
      find.byKey(EmailSignInSteps.emailFieldKey),
      'you@example.com',
    );
    await tester.tap(find.text('Continue'));
    expect(p.log, <String>['address you@example.com']);
    expect(find.byKey(EmailSignInSteps.passwordFieldKey), findsNothing);
  });

  testWidgets('a likely typo is offered, and taken only on a tap', (
    tester,
  ) async {
    final p = _Presses();
    await tester.pumpWidget(
      _host(
        _steps(
          p,
          email: '',
          suggest: (typed) => typed == 'you@gmial.com' ? 'you@gmail.com' : null,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(EmailSignInSteps.emailFieldKey),
      'you@gmial.com',
    );
    await tester.pump();
    expect(find.text('Did you mean you@gmail.com?'), findsOneWidget);

    await tester.tap(find.text('Did you mean you@gmail.com?'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    expect(p.log, <String>['address you@gmail.com']);
  });

  testWidgets('other ways to sign in, only where there are some', (
    tester,
  ) async {
    final p = _Presses();
    await tester.pumpWidget(_host(_steps(p)));
    expect(find.text('Other ways to sign in'), findsNothing);

    await tester.pumpWidget(
      _host(_steps(p, onOtherWays: () => p.log.add('other'))),
    );
    await tester.tap(find.text('Other ways to sign in'));
    expect(p.log, <String>['other']);
  });

  testWidgets('welcome back: the address with Change, and the password', (
    tester,
  ) async {
    final p = _Presses();
    await tester.pumpWidget(_host(_steps(p, stage: EmailStage.password)));

    expect(find.text('you@example.com'), findsOneWidget);
    await tester.enterText(
      find.byKey(EmailSignInSteps.passwordFieldKey),
      'secret',
    );
    await tester.tap(find.text('Sign in'));
    await tester.tap(find.text('Forgot your password?'));
    await tester.tap(find.text('Change'));
    expect(p.log, <String>['password secret', 'forgot', 'change']);
  });

  testWidgets('an Apple account is offered Apple, and a password instead', (
    tester,
  ) async {
    final p = _Presses();
    await tester.pumpWidget(_host(_steps(p, stage: EmailStage.provider)));

    expect(find.text('This address signs in with Apple.'), findsOneWidget);
    await tester.tap(find.text('Continue with Apple'));
    await tester.tap(find.text('Set a password instead'));
    expect(p.log, <String>['provider', 'set password']);
  });

  testWidgets('a Google account is offered Google', (tester) async {
    final p = _Presses();
    await tester.pumpWidget(
      _host(
        _steps(p, stage: EmailStage.provider, provider: SignInProvider.google),
      ),
    );
    expect(find.text('This address signs in with Google.'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('a new account: the rule ticks off as the password is typed', (
    tester,
  ) async {
    final p = _Presses();
    await tester.pumpWidget(
      _host(
        _steps(
          p,
          stage: EmailStage.create,
          requirements: (pw) => <PasswordRequirement>[
            PasswordRequirement('8 characters', met: pw.length >= 8),
            PasswordRequirement('a number', met: pw.contains(RegExp(r'\d'))),
          ],
        ),
      ),
    );

    Icon iconBeside(String label) => tester.widget<Icon>(
      find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
        matching: find.byType(Icon),
      ),
    );

    expect(iconBeside('a number').icon, Icons.radio_button_unchecked);
    await tester.enterText(
      find.byKey(EmailSignInSteps.passwordFieldKey),
      'abc1',
    );
    await tester.pump();
    expect(iconBeside('a number').icon, Icons.check_circle);
    expect(iconBeside('8 characters').icon, Icons.radio_button_unchecked);

    await tester.tap(find.text('Create account'));
    expect(p.log, <String>['create abc1']);
  });

  testWidgets('the sixth digit sends the code', (tester) async {
    final p = _Presses();
    await tester.pumpWidget(_host(_steps(p, stage: EmailStage.code)));

    await tester.enterText(find.byKey(EmailSignInSteps.codeFieldKey), '12345');
    expect(p.log, isEmpty);
    await tester.enterText(find.byKey(EmailSignInSteps.codeFieldKey), '123456');
    expect(p.log, <String>['code 123456']);
  });

  testWidgets('a new code waits, counting down, then may be asked for', (
    tester,
  ) async {
    final p = _Presses();
    var now = DateTime(2026, 10, 19, 9);
    final resendAt = now.add(const Duration(seconds: 42));
    await tester.pumpWidget(
      _host(
        _steps(p, stage: EmailStage.code, resendAt: resendAt, clock: () => now),
      ),
    );

    expect(find.text('Send a new code in 0:42'), findsOneWidget);
    await tester.tap(find.text('Send a new code in 0:42'));
    expect(p.log, isEmpty);

    now = resendAt;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Send a new code'), findsOneWidget);
    await tester.tap(find.text('Send a new code'));
    expect(p.log, <String>['resend']);
  });

  testWidgets('what is said is shown, in its own colour', (tester) async {
    final p = _Presses();
    await tester.pumpWidget(
      _host(
        _steps(
          p,
          stage: EmailStage.password,
          error: 'Wrong password.',
          notice: 'A link is on its way.',
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('Wrong password.')).style?.color,
      AppColors.danger,
    );
    expect(
      tester.widget<Text>(find.text('A link is on its way.')).style?.color,
      AppColors.textSecondary,
    );
  });

  testWidgets('busy, nothing can be pressed twice', (tester) async {
    final p = _Presses();
    await tester.pumpWidget(
      _host(_steps(p, stage: EmailStage.password, busy: true)),
    );
    await tester.tap(find.text('Forgot your password?'));
    await tester.tap(find.text('Change'));
    expect(p.log, isEmpty);
  });

  testWidgets('Change comes back to the address, filled in', (tester) async {
    final p = _Presses();
    await tester.pumpWidget(_host(_steps(p, stage: EmailStage.password)));
    await tester.pumpWidget(_host(_steps(p)));
    expect(
      tester
          .widget<TextField>(find.byKey(EmailSignInSteps.emailFieldKey))
          .controller
          ?.text,
      'you@example.com',
    );
  });

  test('each step says what it is under the head', () {
    expect(EmailStage.address.headline, 'Sign in or create your account');
    expect(EmailStage.password.headline, 'Welcome back');
    expect(EmailStage.provider.headline, 'Welcome back');
    expect(EmailStage.create.headline, 'Create your account');
    expect(EmailStage.code.headline, 'Create your account');
  });

  group('the name step', () {
    testWidgets('starts with what Google sent, and gives back the name', (
      tester,
    ) async {
      String? given = 'unset';
      await tester.pumpWidget(
        _host(AccountNameStep(initial: 'Samuel', onDone: (v) => given = v)),
      );
      expect(find.text('Samuel'), findsOneWidget);

      await tester.enterText(find.byKey(AccountNameStep.fieldKey), '  Sam ');
      await tester.tap(find.text('Continue'));
      expect(given, 'Sam');
    });

    testWidgets('blank, or skipped, is no name', (tester) async {
      final given = <String?>[];
      await tester.pumpWidget(_host(AccountNameStep(onDone: given.add)));
      await tester.tap(find.text('Continue'));
      await tester.tap(find.text('Skip'));
      expect(given, <String?>[null, null]);
    });
  });
}
