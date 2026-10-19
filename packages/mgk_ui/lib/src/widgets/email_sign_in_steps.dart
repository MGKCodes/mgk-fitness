import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'app_buttons.dart';
import 'primary_button.dart';
import 'sign_in_buttons.dart';

/// Which step of the email path is drawn (Run's ADR-0047, "Email first").
///
/// The same five steps as `mgk_auth`'s `EmailStep`, which decides them; this
/// package draws them and never decides.
enum EmailStage {
  /// The address, alone.
  address,

  /// *Welcome back*: a password for an account that has one.
  password,

  /// *This address signs in with Apple* (or Google).
  provider,

  /// *Create your account*: a new password.
  create,

  /// The 6-digit code from the email.
  code;

  /// The line under the suite's head for this step, as both apps' sign-in
  /// screens put it. A new address and an unconfirmed one read the same.
  String get headline => switch (this) {
    address => 'Sign in or create your account',
    password || provider => 'Welcome back',
    create || code => 'Create your account',
  };
}

/// One part of the password rule, and whether what is typed meets it.
@immutable
class PasswordRequirement {
  const PasswordRequirement(this.label, {required this.met});

  final String label;
  final bool met;
}

/// The email path's steps, drawn the same in both apps: the address first,
/// then the one step it leads to.
///
/// **Draws; does not decide.** The step, the address, what is said and
/// whether anything is running all come in from the app's `EmailSignInFlow`
/// (in `mgk_auth`), and every press goes back out through a callback. What
/// this holds is only what is being typed, which survives a failure: a wrong
/// password leaves the address where it was, and no connection leaves both.
///
/// **The address stays on every later step, with Change** (the ADR's edge
/// cases): a typo is fixed where it is seen, not by starting again.
class EmailSignInSteps extends StatefulWidget {
  const EmailSignInSteps({
    super.key,
    required this.stage,
    required this.email,
    required this.onAddress,
    required this.onPassword,
    required this.onForgotPassword,
    required this.onProvider,
    required this.onSetPassword,
    required this.onCreate,
    required this.onCode,
    required this.onResend,
    required this.onChangeAddress,
    this.onOtherWays,
    this.provider = SignInProvider.apple,
    this.busy = false,
    this.providerBusy = false,
    this.error,
    this.notice,
    this.resendAt,
    this.clock = DateTime.now,
    this.suggest,
    this.requirements,
  });

  final EmailStage stage;

  /// The address the later steps are about. On [EmailStage.address] it is
  /// what the field starts with, so Change comes back to it filled in.
  final String email;

  /// Which provider [EmailStage.provider] names and offers.
  final SignInProvider provider;

  /// A request is running: every control waits, and the one that started it
  /// shows so.
  final bool busy;

  /// The provider's sheet is up, on [EmailStage.provider].
  final bool providerBusy;

  /// What went wrong, in the error colour, or null.
  final String? error;

  /// The next thing to do, in the quiet colour, or null.
  final String? notice;

  /// When another code may be asked for. Until then *Send a new code* waits,
  /// counting down.
  final DateTime? resendAt;

  /// Now, for the countdown. A board draws a fixed moment with it.
  final DateTime Function() clock;

  /// The address a typo was probably meant to be, for "Did you mean …?", or
  /// null. Offered under the field; never applied without a tap.
  final String? Function(String typed)? suggest;

  /// The password rule, part by part, for what is typed on
  /// [EmailStage.create]. Null shows no checklist.
  final List<PasswordRequirement> Function(String password)? requirements;

  final ValueChanged<String> onAddress;
  final ValueChanged<String> onPassword;
  final VoidCallback onForgotPassword;
  final VoidCallback onProvider;
  final VoidCallback onSetPassword;
  final ValueChanged<String> onCreate;
  final ValueChanged<String> onCode;
  final VoidCallback onResend;
  final VoidCallback onChangeAddress;

  /// Back to Apple, Google and email, from [EmailStage.address]. Null hides
  /// it, for a screen that opened on the email path and has nothing behind.
  final VoidCallback? onOtherWays;

  /// What a test or a board finds each step's main field by.
  static const Key emailFieldKey = ValueKey<String>('email-address');
  static const Key passwordFieldKey = ValueKey<String>('email-password');
  static const Key codeFieldKey = ValueKey<String>('email-code');

  @override
  State<EmailSignInSteps> createState() => _EmailSignInStepsState();
}

class _EmailSignInStepsState extends State<EmailSignInSteps> {
  late final TextEditingController _email = TextEditingController(
    text: widget.email,
  )..addListener(_typed);
  final TextEditingController _password = TextEditingController();
  final TextEditingController _code = TextEditingController();
  bool _obscure = true;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _password.addListener(_typed);
    _startTicking();
  }

  @override
  void didUpdateWidget(EmailSignInSteps old) {
    super.didUpdateWidget(old);
    if (old.stage != widget.stage) {
      // A new step starts empty, except the address, which is the point of
      // the later steps and the thing Change comes back to.
      _password.clear();
      _code.clear();
      _obscure = true;
      if (widget.stage == EmailStage.address && widget.email.isNotEmpty) {
        _email.text = widget.email;
      }
    }
    if (old.resendAt != widget.resendAt) _startTicking();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Rebuilds as the address and the password are typed, for the suggestion
  /// and the checklist.
  void _typed() => setState(() {});

  /// Ticks once a second while the resend countdown runs, and stops.
  void _startTicking() {
    _tick?.cancel();
    if (_resendIn() == Duration.zero) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {});
      if (_resendIn() == Duration.zero) timer.cancel();
    });
  }

  Duration _resendIn() {
    final at = widget.resendAt;
    if (at == null) return Duration.zero;
    final left = at.difference(widget.clock());
    return left.isNegative ? Duration.zero : left;
  }

  @override
  Widget build(BuildContext context) => Column(
    key: ValueKey<EmailStage>(widget.stage),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: switch (widget.stage) {
      EmailStage.address => _address(context),
      EmailStage.password => _passwordStep(context),
      EmailStage.provider => _provider(context),
      EmailStage.create => _create(context),
      EmailStage.code => _codeStep(context),
    },
  );

  List<Widget> _address(BuildContext context) {
    final suggestion = widget.suggest?.call(_email.text);
    return <Widget>[
      TextField(
        key: EmailSignInSteps.emailFieldKey,
        controller: _email,
        enabled: !widget.busy,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        textInputAction: TextInputAction.go,
        autofillHints: const <String>[AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email'),
        onSubmitted: (_) => _submitAddress(),
      ),
      if (suggestion != null) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: AppTextButton(
            label: 'Did you mean $suggestion?',
            onPressed: widget.busy
                ? null
                : () => _email.value = TextEditingValue(
                    text: suggestion,
                    selection: TextSelection.collapsed(
                      offset: suggestion.length,
                    ),
                  ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      PrimaryButton(
        label: 'Continue',
        busy: widget.busy,
        onPressed: _submitAddress,
      ),
      ..._messages(context),
      if (widget.onOtherWays != null) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        AppTextButton(
          label: 'Other ways to sign in',
          onPressed: widget.busy ? null : widget.onOtherWays,
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
      ],
    ];
  }

  void _submitAddress() {
    if (widget.busy) return;
    widget.onAddress(_email.text);
  }

  List<Widget> _passwordStep(BuildContext context) => <Widget>[
    _AddressRow(
      email: widget.email,
      onChange: widget.busy ? null : widget.onChangeAddress,
    ),
    const SizedBox(height: AppSpacing.md),
    _passwordField(newPassword: false, onSubmitted: _submitPassword),
    const SizedBox(height: AppSpacing.lg),
    PrimaryButton(
      label: 'Sign in',
      busy: widget.busy,
      onPressed: _submitPassword,
    ),
    ..._messages(context),
    const SizedBox(height: AppSpacing.xs),
    AppTextButton(
      label: 'Forgot your password?',
      onPressed: widget.busy ? null : widget.onForgotPassword,
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
    ),
  ];

  void _submitPassword() {
    if (widget.busy) return;
    widget.onPassword(_password.text);
  }

  List<Widget> _provider(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.provider == SignInProvider.apple ? 'Apple' : 'Google';
    return <Widget>[
      _AddressRow(
        email: widget.email,
        onChange: widget.busy || widget.providerBusy
            ? null
            : widget.onChangeAddress,
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(
        'This address signs in with $name.',
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: AppSpacing.lg),
      switch (widget.provider) {
        SignInProvider.apple => ProviderSignInButton.apple(
          busy: widget.providerBusy,
          onPressed: widget.busy ? null : widget.onProvider,
        ),
        SignInProvider.google => ProviderSignInButton.google(
          busy: widget.providerBusy,
          onPressed: widget.busy ? null : widget.onProvider,
        ),
      },
      ..._messages(context),
      const SizedBox(height: AppSpacing.xs),
      AppTextButton(
        label: 'Set a password instead',
        busy: widget.busy,
        onPressed: widget.providerBusy ? null : widget.onSetPassword,
        style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      ),
    ];
  }

  List<Widget> _create(BuildContext context) {
    final theme = Theme.of(context);
    final requirements = widget.requirements?.call(_password.text);
    return <Widget>[
      _AddressRow(
        email: widget.email,
        onChange: widget.busy ? null : widget.onChangeAddress,
      ),
      const SizedBox(height: AppSpacing.md),
      _passwordField(newPassword: true, onSubmitted: _submitCreate),
      if (requirements != null) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        _Requirements(requirements),
      ],
      const SizedBox(height: AppSpacing.lg),
      PrimaryButton(
        label: 'Create account',
        busy: widget.busy,
        onPressed: _submitCreate,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'We will email a 6-digit code to check the address is yours.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textTertiary,
          height: 1.4,
        ),
      ),
      ..._messages(context),
    ];
  }

  void _submitCreate() {
    if (widget.busy) return;
    widget.onCreate(_password.text);
  }

  List<Widget> _codeStep(BuildContext context) {
    final theme = Theme.of(context);
    final left = _resendIn();
    final seconds = left.inSeconds + (left.inMilliseconds % 1000 > 0 ? 1 : 0);
    final wait =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return <Widget>[
      Text(
        'Enter the 6-digit code we sent to',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      _AddressRow(
        email: widget.email,
        onChange: widget.busy ? null : widget.onChangeAddress,
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        key: EmailSignInSteps.codeFieldKey,
        controller: _code,
        enabled: !widget.busy,
        autofocus: true,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 6,
        // Mail offers the code above the keyboard on iOS.
        autofillHints: const <String>[AutofillHints.oneTimeCode],
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        style: theme.textTheme.headlineSmall?.copyWith(
          letterSpacing: 8,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
        decoration: const InputDecoration(counterText: '', hintText: '000000'),
        onChanged: (value) {
          // The sixth digit is the press: a code pasted or filled from Mail
          // goes without a second tap.
          if (value.length == 6) _submitCode();
        },
        onSubmitted: (_) => _submitCode(),
      ),
      const SizedBox(height: AppSpacing.lg),
      PrimaryButton(
        label: 'Confirm',
        busy: widget.busy,
        onPressed: _submitCode,
      ),
      ..._messages(context),
      const SizedBox(height: AppSpacing.xs),
      AppTextButton(
        label: left == Duration.zero
            ? 'Send a new code'
            : 'Send a new code in $wait',
        onPressed: widget.busy || left != Duration.zero
            ? null
            : widget.onResend,
        style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      ),
    ];
  }

  void _submitCode() {
    if (widget.busy) return;
    widget.onCode(_code.text);
  }

  Widget _passwordField({
    required bool newPassword,
    required VoidCallback onSubmitted,
  }) => TextField(
    key: EmailSignInSteps.passwordFieldKey,
    controller: _password,
    enabled: !widget.busy,
    autofocus: true,
    obscureText: _obscure,
    textInputAction: TextInputAction.go,
    // A new password lets the phone suggest a strong one; an existing one lets
    // it fill the saved one.
    autofillHints: <String>[
      newPassword ? AutofillHints.newPassword : AutofillHints.password,
    ],
    decoration: InputDecoration(
      labelText: newPassword ? 'Choose a password' : 'Password',
      suffixIcon: AppIconButton(
        onPressed: () => setState(() => _obscure = !_obscure),
        icon: _obscure
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
        tooltip: _obscure ? 'Show password' : 'Hide password',
      ),
    ),
    onSubmitted: (_) => onSubmitted(),
  );

  List<Widget> _messages(BuildContext context) {
    final theme = Theme.of(context);
    return <Widget>[
      if (widget.error != null) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        Text(
          widget.error!,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
        ),
      ],
      if (widget.notice != null) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        Text(
          widget.notice!,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    ];
  }
}

/// The address a later step is about, with Change beside it.
class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.email, required this.onChange});

  final String email;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.controlAll,
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.lg),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.mail_outline,
              size: 18,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            AppTextButton(label: 'Change', onPressed: onChange),
          ],
        ),
      ),
    );
  }
}

/// The password rule as a checklist, each part ticked as it is met.
///
/// Greyscale on purpose: a part met is drawn in full, a part not met is
/// faint, and nothing turns green or red while somebody is still typing.
class _Requirements extends StatelessWidget {
  const _Requirements(this.requirements);

  final List<PasswordRequirement> requirements;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        for (final r in requirements)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                r.met ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14,
                color: r.met ? AppColors.textPrimary : AppColors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                r.label,
                style: style?.copyWith(
                  color: r.met ? AppColors.textPrimary : AppColors.textTertiary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// The one optional step after a new account: what to call its owner
/// (ADR-0047, "The name belongs to the account").
///
/// **Never shown after Sign in with Apple**, which is the app's to keep to:
/// App Review rejected Run 1.0.0 for asking after it, though the question
/// could be skipped. Starts filled in with what Google sent, when the account
/// came from Google, and is as easy to clear as to keep.
class AccountNameStep extends StatefulWidget {
  const AccountNameStep({
    super.key,
    required this.onDone,
    this.initial,
    this.busy = false,
    this.error,
  });

  /// The name to start with, or null for an empty field.
  final String? initial;

  /// The name given, trimmed, or null when skipped or left blank.
  final ValueChanged<String?> onDone;

  final bool busy;
  final String? error;

  static const Key fieldKey = ValueKey<String>('account-name');

  @override
  State<AccountNameStep> createState() => _AccountNameStepState();
}

class _AccountNameStepState extends State<AccountNameStep> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    if (widget.busy) return;
    final value = _name.text.trim();
    widget.onDone(value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'What should we call you?',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your first name, the same in both apps. You can leave it blank and '
          'add it later.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          key: AccountNameStep.fieldKey,
          controller: _name,
          enabled: !widget.busy,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.givenName],
          decoration: const InputDecoration(labelText: 'First name'),
          onSubmitted: (_) => _done(),
        ),
        if (widget.error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            widget.error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(label: 'Continue', busy: widget.busy, onPressed: _done),
        const SizedBox(height: AppSpacing.xs),
        AppTextButton(
          label: 'Skip',
          onPressed: widget.busy ? null : () => widget.onDone(null),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
      ],
    );
  }
}
