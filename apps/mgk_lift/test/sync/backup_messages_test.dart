import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/sync/domain/sync_status.dart';
import 'package:mgk_lift/src/features/sync/presentation/backup_messages.dart';
import 'package:mgk_lift/src/features/sync/presentation/backup_scheduler.dart';

/// What each surface says about backup. One set of rules, so the summary, the
/// pill and Settings cannot contradict each other.
void main() {
  final finished = DateTime(2026, 9, 29, 19);

  BackupStatus at(
    BackupState state, {
    Set<String> waiting = const <String>{},
    int sessions = 0,
    int saved = 0,
    DateTime? lastRun,
    List<RejectedWorkout> rejected = const <RejectedWorkout>[],
  }) => BackupStatus(
    state: state,
    pending: SyncPending(
      workouts: sessions,
      savedWorkouts: saved,
      lastSyncedAt: lastRun,
      waitingIds: waiting,
      rejected: rejected,
    ),
  );

  group('the summary', () {
    String say(BackupStatus s) =>
        sessionBackupMessage(s, sessionId: 's', finishedAt: finished).text;

    test('saved on this phone first — that is true at once', () {
      expect(
        say(at(BackupState.idle, waiting: <String>{'s'}, sessions: 1)),
        'Saved on this phone.',
      );
      expect(
        say(at(BackupState.running, waiting: <String>{'s'}, sessions: 1)),
        'Saved on this phone. Backing up…',
      );
    });

    test('backed up only after a run that finished after the session', () {
      // Nothing waiting, but no run since Finish: the queue has not been read
      // yet, and "not read" is not "sent".
      expect(say(at(BackupState.idle)), 'Saved on this phone.');
      expect(
        say(
          at(
            BackupState.idle,
            lastRun: finished.subtract(const Duration(minutes: 5)),
          ),
        ),
        'Saved on this phone.',
      );
      expect(
        say(
          at(
            BackupState.idle,
            lastRun: finished.add(const Duration(seconds: 3)),
          ),
        ),
        'Backed up.',
      );
    });

    test('each problem in words, with the one thing that fixes it', () {
      final offline = sessionBackupMessage(
        at(BackupState.offline, waiting: <String>{'s'}),
        sessionId: 's',
        finishedAt: finished,
      );
      expect(offline.text, contains("It'll back up when you're online"));
      expect(offline.action, BackupAction.none);

      final failed = sessionBackupMessage(
        at(BackupState.failed, waiting: <String>{'s'}),
        sessionId: 's',
        finishedAt: finished,
      );
      expect(failed.action, BackupAction.retry);

      final expired = sessionBackupMessage(
        at(BackupState.expired, waiting: <String>{'s'}),
        sessionId: 's',
        finishedAt: finished,
      );
      expect(expired.text, contains('Sign in again'));
      expect(expired.action, BackupAction.signIn);
    });

    test('signed out, the fact and nothing after it', () {
      // The account card's rule, here too: state it, do not sell it.
      final m = sessionBackupMessage(
        at(BackupState.signedOut, waiting: <String>{'s'}),
        sessionId: 's',
        finishedAt: finished,
      );
      expect(m.text, 'Saved on this phone.');
      expect(m.action, BackupAction.none);
    });

    test('a refusal of this session says why', () {
      expect(
        say(
          at(
            BackupState.idle,
            rejected: const <RejectedWorkout>[
              RejectedWorkout(
                id: 's',
                name: 'Push',
                isTemplate: false,
                detail: '22003: x',
              ),
            ],
          ),
        ),
        "Saved on this phone, but it couldn't be backed up: a value is out "
        'of range.',
      );
    });
  });

  group("Track's pill", () {
    test('nothing when all is well, or while it runs', () {
      expect(trackBackupMessage(at(BackupState.idle)), isNull);
      expect(trackBackupMessage(at(BackupState.running, sessions: 2)), isNull);
    });

    test('nothing for somebody who has never signed in', () {
      // Track is the screen opened most. A permanent line about an account
      // they chose not to make is nagging.
      expect(
        trackBackupMessage(at(BackupState.signedOut, sessions: 9)),
        isNull,
      );
    });

    test('what is waiting, offline — no action, it goes by itself', () {
      expect(
        trackBackupMessage(at(BackupState.offline, sessions: 1, saved: 1)),
        const BackupMessage('1 session and 1 saved workout waiting to back up'),
      );
    });

    test('a failure with work waiting offers a retry', () {
      expect(
        trackBackupMessage(at(BackupState.failed, sessions: 2)),
        const BackupMessage('Backup failed', action: BackupAction.retry),
      );
      // Nothing waiting, nothing to say.
      expect(trackBackupMessage(at(BackupState.failed)), isNull);
    });

    test('a lapsed sign-in asks for one', () {
      expect(
        trackBackupMessage(at(BackupState.expired))?.action,
        BackupAction.signIn,
      );
    });

    test('a refusal names the workout and sends to the list', () {
      final m = trackBackupMessage(
        at(
          BackupState.idle,
          rejected: const <RejectedWorkout>[
            RejectedWorkout(
              id: 'w',
              name: 'Push',
              isTemplate: true,
              detail: '23514: x',
            ),
          ],
        ),
      );
      expect(m?.text, '"Push" couldn\'t be backed up');
      expect(m?.action, BackupAction.review);
    });
  });

  test('waitingPhrase counts sessions and saved workouts apart', () {
    SyncPending p(int a, int b) =>
        SyncPending(workouts: a, savedWorkouts: b, lastSyncedAt: null);
    expect(waitingPhrase(p(0, 0)), isNull);
    expect(waitingPhrase(p(1, 0)), '1 session');
    expect(waitingPhrase(p(0, 2)), '2 saved workouts');
    expect(waitingPhrase(p(3, 1)), '3 sessions and 1 saved workout');
  });
}
