import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mgk_auth/mgk_auth.dart'
    show AccountStatus, EmailSignInFlow, EmailStep, PasswordCheck;
import 'package:mgk_ui/mgk_ui.dart';

import '../../../core/brand.dart';
import '../../legal/domain/legal_copy.dart';
import '../../legal/domain/legal_document.dart';
import '../../legal/presentation/legal_document_screen.dart';
import '../domain/account.dart';

/// Sign in, or make an account: with Apple, with Google, or with an email.
///
/// **Apple and Google first, email one tap behind them (R10).** Most people
/// arriving here already have one of the two on the phone, and for them it is
/// one tap and no password; the design review found the email form was the
/// whole screen, with nothing to say that anything else was possible. Google
/// is only offered beside Apple (App Store guideline 4.8), and the two are
/// drawn with equal weight.
///
/// **Set on a photograph (R1).** This is one of the two screens that lead with
/// one; the headline and the choices sit low, over the dark floor the image
/// was composed with.
///
/// **Headed by the app, then the account.** Lift's icon and name come first,
/// so nobody wonders which app they are signing in to, and then the suite's
/// head ([ProfileHeader], which Run's sign-in draws too, with Run's icon): an
/// MGKFitness Account, the same one Run signs into. It used to read "Sign in", with nothing to say
/// whose account it was, which app it was for, or that Run's would work.
///
/// **The address first, and the lookup decides what comes next** (Run's
/// ADR-0047, from 2.0.1). *Continue with email* asks for the address alone;
/// `mgk_auth`'s [EmailSignInFlow] looks it up and moves to *Welcome back*,
/// *This address signs in with Apple* (or Google), or *Create your account*
/// and a 6-digit code. Nobody has to know before they type whether they are
/// signing in or signing up, which is what the two-mode form and its switch
/// asked of them until 2.0.0. The steps are `mgk_ui`'s [EmailSignInSteps],
/// drawn and worded as Run's are; this screen owns the flow and decides only
/// what happens once somebody is signed in.
///
/// **A new account is asked, once, what to call its owner** ([AccountNameStep],
/// in place of the form): after an account made with an address, or with
/// Google, which starts it filled in with Google's first name. **Never after
/// Apple**, by any route, the browser's on Android included: App Review
/// rejected Run 1.0.0 for asking after Sign in with Apple, though the question
/// could be skipped (guideline 4, 16 October 2026). Skipping writes nothing,
/// and the name can be given later on the account screen. A returning account
/// is not asked.
///
/// **Opened on purpose, and only for two things:** to sign in and back up,
/// from Settings, or to have an account for a subscription to belong to, from
/// the sales screen. Tracking never needs one, so the screen does not stand in
/// front of anything and back is always one tap. It used to end on "You do not
/// need an account to track your training", which on a screen somebody had
/// just asked for read as a contradiction: it is gone.
///
/// Pops with true once somebody is signed in, after the name step when there
/// is one.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.auth,
    this.pendingWorkouts = 0,
    this.emailFirst = false,
    this.clock = DateTime.now,
  });

  final AuthService auth;

  /// How many sessions exist only on this phone. Shown as the reason to bother,
  /// because it is the true one and it is specific.
  final int pendingWorkouts;

  /// Opens on the address rather than the three choices, with *Other ways to
  /// sign in* under it.
  final bool emailFirst;

  /// Now, for the wait before another code can be sent. A board draws a fixed
  /// moment with it.
  final DateTime Function() clock;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  /// The email path: which step, the address, what is said, and the wait for
  /// another code. Owned here; its workings and its words are shared with
  /// Run's screen.
  late final EmailSignInFlow _flow = EmailSignInFlow(
    api: widget.auth.emailSignIn,
    clock: widget.clock,
  )..addListener(_redraw);

  late bool _withEmail = widget.emailFirst;
  SignInProvider? _asking;
  String? _error;
  String? _notice;

  /// Watches for an account arriving from outside this screen: Apple's sign-in
  /// on Android finishes in the browser and comes back through a link.
  StreamSubscription<Account?>? _arrivals;

  /// Popped already. Two things can finish a sign-in — the call that made it
  /// and the stream that reports it — and only one of them may close the
  /// screen, or the second would close whatever was under it.
  bool _done = false;

  /// One of this screen's own sign-in calls is running. **The stream waits
  /// for it**: the stream reports the account before the call has returned,
  /// and only the call knows whether the account is new (a code that checked
  /// out made one; a password signed into one). Left to the stream, a new
  /// account would be closed past its name step.
  bool _calling = false;

  /// The stream reported an account while [_calling] or [_asking]: the
  /// sign-in happened, whatever the call goes on to say about what came after
  /// it.
  bool _arrivedDuringCall = false;

  /// On the name step, with what it starts filled in with. Null on every
  /// other step, and once it is set nothing else may close the screen but
  /// the step's own answer.
  _Naming? _naming;
  bool _savingName = false;
  String? _nameError;

  /// The name has failed to save once and been said so. The next press goes
  /// on, whatever the server says: a name is never worth being stuck for.
  bool _nameFailed = false;

  bool get _anyBusy => _flow.busy || _asking != null || _savingName;

  @override
  void initState() {
    super.initState();
    _arrivals = widget.auth.changes.listen(_arrived);
  }

  @override
  void dispose() {
    unawaited(_arrivals?.cancel());
    _flow
      ..removeListener(_redraw)
      ..dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(true);
  }

  /// An account on the stream. Acted on only when nothing of this screen's is
  /// running, which in practice is Apple's browser sign-in on Android: its
  /// call returned [ProviderOutcome.continuing] long before, so whether the
  /// account is new is read from the account, and an Apple account is never
  /// asked its name there either.
  void _arrived(Account? account) {
    if (account == null || _done || _naming != null) return;
    if (_calling || _asking != null) {
      _arrivedDuringCall = true;
      return;
    }
    _signedIn(isNew: widget.auth.isNewAccount);
  }

  /// Somebody is signed in. A new account that cannot sign in with Apple is
  /// asked its name; everybody else is done.
  void _signedIn({required bool isNew}) {
    if (_done || _naming != null || !mounted) return;
    if (!isNew || widget.auth.signsInWithApple) return _finish();
    setState(() {
      _naming = _Naming(widget.auth.googleFirstName);
      _error = null;
      _notice = null;
    });
  }

  Future<void> _withProvider(SignInProvider provider) async {
    if (_anyBusy || _naming != null) return;
    _flow.clearMessages();
    _arrivedDuringCall = false;
    setState(() {
      _asking = provider;
      _error = null;
      _notice = null;
    });
    try {
      final outcome = switch (provider) {
        SignInProvider.apple => await widget.auth.signInWithApple(),
        SignInProvider.google => await widget.auth.signInWithGoogle(),
      };
      if (!mounted) return;
      switch (outcome) {
        case ProviderOutcome.signedIn:
          setState(() => _asking = null);
          // Apple and Google make an account or sign into one without saying
          // which, so the account says.
          _signedIn(isNew: widget.auth.isNewAccount);
        case ProviderOutcome.cancelled:
          // Closing Apple's or Google's sheet is a choice, not a failure, and
          // a message would read as one.
          setState(() => _asking = null);
        case ProviderOutcome.continuing:
          setState(() {
            _asking = null;
            _notice = 'Finish signing in with Apple in your browser.';
          });
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _asking = null;
        _error = e.failure.message;
      });
    }
  }

  /// One step of the email path that can sign somebody in, run so the stream
  /// waits for it ([_calling]).
  ///
  /// [madeAccount] is what a success means: a code that checked out, or an
  /// account the project signed in at once, made one; a password signed into
  /// one. **A sign-in the stream saw still counts when the call then failed**:
  /// a code can check out and the password typed for an unconfirmed address
  /// fail to replace the first one (the same password twice is refused), and
  /// the account is signed in all the same. Stopping there would leave a
  /// signed-in lifter in front of a code that no longer works.
  Future<void> _emailCall(
    Future<bool> Function() call, {
    required bool madeAccount,
  }) async {
    if (_calling || _anyBusy) return;
    _clearOwnMessages();
    _calling = true;
    _arrivedDuringCall = false;
    bool ok;
    try {
      ok = await call();
    } finally {
      _calling = false;
    }
    if (!mounted) return;
    if (ok || (_arrivedDuringCall && widget.auth.current != null)) {
      _signedIn(isNew: madeAccount);
    }
  }

  /// What the screen said itself, about Apple or Google, goes as soon as the
  /// email path is used: the flow says its own.
  void _clearOwnMessages() {
    if (_error == null && _notice == null) return;
    setState(() {
      _error = null;
      _notice = null;
    });
  }

  void _showEmail(bool show) {
    _flow.clearMessages();
    setState(() {
      _withEmail = show;
      _error = null;
      _notice = null;
    });
  }

  /// The name step's answer. Skipping, or leaving it blank, writes nothing.
  Future<void> _named(String? name) async {
    if (_savingName || _done) return;
    if (name == null) return _finish();
    setState(() {
      _savingName = true;
      _nameError = null;
    });
    try {
      await widget.auth.updateName(name);
      if (!mounted) return;
      _finish();
    } on AuthException {
      if (!mounted) return;
      // Said once, then out of the way: the account is made and signed in,
      // and the name can be given on the account screen whenever.
      if (_nameFailed) return _finish();
      setState(() {
        _savingName = false;
        _nameFailed = true;
        _nameError =
            'Your name did not save. You can add it later in Settings.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final naming = _naming != null;

    // Backing out mid-request would leave the lifter on Track not knowing
    // whether they are signed in — the request completes either way, and the
    // stream that reports it fires into a disposed screen. Two seconds of a
    // disabled arrow is the cheaper confusion.
    //
    // **On the name step, back is Skip.** The account is made and signed in
    // by then, so leaving has to say so: closing with nothing would tell the
    // sales screen there is no account, and the purchase would not go on.
    return PopScope(
      canPop: !_anyBusy && !naming,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && naming && !_savingName) _finish();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: PhotoBackdrop.hero(
          image: 'assets/images/backgrounds/hero_sign_in.webp',
          child: Stack(
            children: <Widget>[
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    // Anchored to the bottom, so with the keyboard up the
                    // field being typed in and its button stay in view and
                    // the headline is what scrolls away.
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xxl + AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.lg,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            constraints.maxHeight -
                            AppSpacing.xxl -
                            AppSpacing.xl -
                            AppSpacing.lg,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          ProfileHeader(
                            line: _line,
                            otherApp: 'Run',
                            app: const AppIdentity(
                              icon: AssetImage(
                                'assets/images/brand/app_icon.png',
                              ),
                              name: kAppName,
                            ),
                          ),
                          if (_pending() case final String fact) ...<Widget>[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              fact,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          AnimatedSize(
                            duration: AppMotion.base,
                            curve: AppMotion.standard,
                            alignment: Alignment.bottomCenter,
                            child: naming
                                ? _nameStep()
                                : _withEmail
                                ? _emailSteps()
                                : _choices(theme),
                          ),
                          // The email path and the name step say their own;
                          // these are Apple's and Google's, on the choices.
                          if (!naming && !_withEmail) ..._messages(theme),
                          // Required wherever an account can be created, and
                          // this screen is the only place it can be. Shown on
                          // every step: somebody signing in on a new phone is
                          // re-accepting the same terms, and a link that
                          // appears and disappears reads as a trick.
                          const SizedBox(height: AppSpacing.xl),
                          const _LegalLinks(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: top + AppSpacing.xs,
                left: AppSpacing.sm,
                child: AppIconButton(
                  icon: backIcon(context),
                  tooltip: 'Back',
                  onPressed: _anyBusy
                      ? null
                      : naming
                      ? _finish
                      : () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What this visit is, under the suite's name.
  ///
  /// On the choices it says both, because Apple and Google do both without
  /// being told which, and "Sign in" alone reads as a door for people who
  /// already have an account. On the email path it is the step's own line,
  /// which Run's screen uses too; the name step is the last of making the
  /// account.
  String get _line {
    if (_naming != null) return EmailStage.create.headline;
    if (!_withEmail) return 'Sign in or create your account';
    return _stage.headline;
  }

  EmailStage get _stage => switch (_flow.step) {
    EmailStep.address => EmailStage.address,
    EmailStep.password => EmailStage.password,
    EmailStep.provider => EmailStage.provider,
    EmailStep.create => EmailStage.create,
    EmailStep.code => EmailStage.code,
  };

  /// The one fact worth adding, or null when there is none: sessions that
  /// exist in a single place. That is state the person may not have, not an
  /// argument for the account. *Welcome back* and *This address signs in
  /// with Apple* get nothing more, because somebody with an account knows
  /// what it does; nor does the name step, which comes after the account
  /// that backs them up.
  String? _pending() {
    final n = widget.pendingWorkouts;
    if (n == 0 || _naming != null) return null;
    if (_withEmail &&
        (_flow.step == EmailStep.password ||
            _flow.step == EmailStep.provider)) {
      return null;
    }
    return '$n session${n == 1 ? '' : 's'} ${n == 1 ? 'is' : 'are'} on this '
        'phone only.';
  }

  List<Widget> _messages(ThemeData theme) => <Widget>[
    if (_error != null) ...<Widget>[
      const SizedBox(height: AppSpacing.md),
      Text(
        _error!,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
      ),
    ],
    if (_notice != null) ...<Widget>[
      const SizedBox(height: AppSpacing.md),
      Text(
        _notice!,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    ],
  ];

  Widget _choices(ThemeData theme) => Column(
    key: const ValueKey<String>('choices'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      ProviderSignInButton.apple(
        busy: _asking == SignInProvider.apple,
        onPressed: _anyBusy ? null : () => _withProvider(SignInProvider.apple),
      ),
      const SizedBox(height: AppSpacing.md),
      ProviderSignInButton.google(
        busy: _asking == SignInProvider.google,
        onPressed: _anyBusy ? null : () => _withProvider(SignInProvider.google),
      ),
      const SizedBox(height: AppSpacing.md),
      AppOutlinedButton(
        label: 'Continue with email',
        icon: Icons.mail_outline,
        expand: true,
        onPressed: _anyBusy ? null : () => _showEmail(true),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        // O2. Apple's relay address is a different address, so Supabase has
        // nothing to join it to an existing account by.
        'Choosing Hide My Email with Apple starts a separate account.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textTertiary,
          height: 1.4,
        ),
      ),
    ],
  );

  /// The provider an address signs in with, on *This address signs in
  /// with…*. Apple until the lookup has said otherwise.
  SignInProvider get _addressProvider => _flow.status == AccountStatus.google
      ? SignInProvider.google
      : SignInProvider.apple;

  Widget _emailSteps() => KeyedSubtree(
    key: const ValueKey<String>('email'),
    child: EmailSignInSteps(
      stage: _stage,
      email: _flow.email,
      provider: _addressProvider,
      busy: _flow.busy,
      providerBusy: _asking != null,
      // Apple's or Google's own failure, from *This address signs in with…*,
      // in the place the flow says its own.
      error: _flow.error ?? _error,
      notice: _flow.notice ?? _notice,
      resendAt: _flow.resendAt,
      clock: widget.clock,
      suggest: _flow.suggestionFor,
      requirements: _requirements,
      onAddress: (typed) {
        _clearOwnMessages();
        unawaited(_flow.submitAddress(typed));
      },
      onPassword: (password) => unawaited(
        _emailCall(() => _flow.signIn(password), madeAccount: false),
      ),
      onForgotPassword: () {
        _clearOwnMessages();
        unawaited(_flow.forgotPassword());
      },
      onProvider: () => unawaited(_withProvider(_addressProvider)),
      onSetPassword: () {
        _clearOwnMessages();
        unawaited(_flow.setPasswordInstead());
      },
      onCreate: (password) => unawaited(
        _emailCall(() => _flow.createAccount(password), madeAccount: true),
      ),
      onCode: (code) =>
          unawaited(_emailCall(() => _flow.confirm(code), madeAccount: true)),
      onResend: () {
        _clearOwnMessages();
        unawaited(_flow.resend());
      },
      onChangeAddress: () {
        _clearOwnMessages();
        _flow.changeAddress();
      },
      onOtherWays: () => _showEmail(false),
    ),
  );

  /// The password rule, part by part, in the words Run's screen uses.
  static List<PasswordRequirement> _requirements(String password) {
    final check = PasswordCheck.of(password);
    return <PasswordRequirement>[
      PasswordRequirement('8 characters', met: check.longEnough),
      PasswordRequirement('a number', met: check.hasNumber),
      PasswordRequirement('a symbol', met: check.hasSymbol),
    ];
  }

  Widget _nameStep() => KeyedSubtree(
    key: const ValueKey<String>('name'),
    child: AccountNameStep(
      initial: _naming?.prefill,
      busy: _savingName,
      error: _nameError,
      onDone: (name) => unawaited(_named(name)),
    ),
  );
}

/// The name step, and what it starts filled in with: Google's first name for
/// an account made with Google, nothing for one made with an address.
@immutable
class _Naming {
  const _Naming(this.prefill);

  final String? prefill;
}

/// The terms and privacy links under the sign-in form.
///
/// One sentence with two tappable halves rather than two buttons. Apple wants
/// the documents reachable from the point of account creation; a person wants
/// to know what they are agreeing to. A sentence does both, and two more
/// buttons under the primary action would compete with it.
class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  void _open(BuildContext context, LegalDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(document: document),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      height: 1.4,
    );
    final link = base?.copyWith(
      color: AppColors.textSecondary,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.textTertiary,
    );

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          const TextSpan(text: 'By continuing you agree to the '),
          TextSpan(
            text: termsOfUse.title.toLowerCase(),
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _open(context, termsOfUse),
          ),
          const TextSpan(text: ' and the '),
          TextSpan(
            text: privacyPolicy.title.toLowerCase(),
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _open(context, privacyPolicy),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
      style: base,
    );
  }
}
