import 'package:flutter/foundation.dart';

/// The rule for a new password, written once for both apps and the reset page
/// to agree with (Run's ADR-0047, "The password rule").
///
/// **At least 8 characters, at least one number and at least one symbol.** A
/// symbol is anything that is not a letter or a number, so a hyphen or a space
/// counts: the passwords iOS suggests are letters joined by hyphens, and they
/// must pass without being edited.
///
/// Checked when an account is made and when a password is set or reset.
/// **Signing in never checks it**: an account keeps whatever password it was
/// made with, and refusing to send one that the server would accept locks
/// somebody out of their own account.
///
/// The server's minimum is 8 as well. Its character rules stay off, because
/// none of Supabase's choices is "a number and a symbol", and turning one on
/// would fail sign-ups from apps that do not explain it.
@immutable
class PasswordCheck {
  const PasswordCheck._({
    required this.longEnough,
    required this.hasNumber,
    required this.hasSymbol,
  });

  /// Checks [password] against each part of the rule.
  ///
  /// Length counts characters as a person sees them (code points), not bytes,
  /// so a password of accented letters is not cut short. The server counts
  /// bytes, which can only make its minimum easier to meet than this one.
  factory PasswordCheck.of(String password) {
    var length = 0;
    var number = false;
    var symbol = false;
    for (final rune in password.runes) {
      length++;
      final char = String.fromCharCode(rune);
      if (_number.hasMatch(char)) {
        number = true;
      } else if (!_letter.hasMatch(char)) {
        symbol = true;
      }
    }
    return PasswordCheck._(
      longEnough: length >= minimumLength,
      hasNumber: number,
      hasSymbol: symbol,
    );
  }

  /// The fewest characters a new password may have.
  static const int minimumLength = 8;

  /// Letters in any script, with the marks that sit on them, so `é` written as
  /// `e` and a combining accent is still a letter rather than a symbol.
  static final RegExp _letter = RegExp(r'[\p{L}\p{M}]', unicode: true);

  /// Numbers in any script.
  static final RegExp _number = RegExp(r'\p{N}', unicode: true);

  final bool longEnough;
  final bool hasNumber;
  final bool hasSymbol;

  /// Whether every part of the rule is met.
  bool get passes => longEnough && hasNumber && hasSymbol;
}
