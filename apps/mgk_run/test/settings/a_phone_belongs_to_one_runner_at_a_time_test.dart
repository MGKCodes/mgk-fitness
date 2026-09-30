import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_auth/mgk_auth.dart';

/// **The rule about whose training is on the phone.**
///
/// Nothing on the phone said who it belonged to, so the second account to sign
/// in was treated as the first: the restore and backfill ran for them, the
/// first runner's runs and traces went up into their account, and they saw
/// the first runner's log, plan, injury notes and coach transcripts.
///
/// The rule: an empty phone has no owner; the first account to sign in while
/// training is here claims it; a different account is asked before anything
/// happens.
void main() {
  late InMemoryLocalDataOwner owner;
  late _Training data;
  late LocalDataGuard guard;

  setUp(() {
    owner = InMemoryLocalDataOwner();
    data = _Training();
    guard = LocalDataGuard(owner: owner, data: data);
  });

  test(
    'the first account to sign in claims the training already here',
    () async {
      // The ordinary path: weeks of runs with no account, then an account.
      data.hasTraining = true;

      expect(await guard.mayUse('alex'), isTrue);
      expect(await owner.read(), 'alex');
      expect(data.erased, 0, reason: 'claiming is not erasing');
    },
  );

  test('the same account signing back in is not asked', () async {
    data.hasTraining = true;
    await owner.write('alex');

    expect(await guard.mayUse('alex'), isTrue);
    expect(data.erased, 0);
  });

  test('a different account is asked while training is here', () async {
    data.hasTraining = true;
    await owner.write('alex');

    expect(await guard.mayUse('sam'), isFalse);
    expect(await owner.read(), 'alex', reason: 'nothing changes hands');
    expect(data.erased, 0, reason: 'and nothing is erased without asking');
  });

  test('a phone with nothing on it belongs to whoever signs in next', () async {
    await owner.write('alex');

    expect(await guard.mayUse('sam'), isTrue);
    expect(await owner.read(), 'sam');
    // What Alex left that is not training -- the backup answer, the record of
    // the last push -- goes, so none of it greets Sam.
    expect(data.erased, 1);
  });

  test('one answer per account, shared by everybody who asks', () async {
    data.hasTraining = true;
    await owner.write('alex');

    final both = await Future.wait(<Future<bool>>[
      guard.mayUse('sam'),
      guard.mayUse('sam'),
    ]);
    expect(both, <bool>[false, false]);
    expect(data.reads, 1, reason: 'the gate and the shell ask within a frame');
  });

  test('erasing for an account hands the phone to it', () async {
    data.hasTraining = true;
    await owner.write('alex');
    expect(await guard.mayUse('sam'), isFalse);

    var told = 0;
    guard.erasures.addListener(() => told++);
    await guard.eraseFor('sam');

    expect(data.erased, 1);
    expect(data.hasTraining, isFalse);
    expect(await owner.read(), 'sam');
    expect(await guard.mayUse('sam'), isTrue);
    expect(told, 1, reason: 'whatever holds the old training in memory hears');
  });

  test('an erase that fails hands nothing over', () async {
    data
      ..hasTraining = true
      ..failErase = true;
    await owner.write('alex');

    await expectLater(guard.eraseFor('sam'), throwsA(isA<StateError>()));
    expect(await owner.read(), 'alex');
    expect(await guard.mayUse('sam'), isFalse);
  });

  test('erasing on the way out leaves the phone unclaimed', () async {
    data.hasTraining = true;
    await owner.write('alex');
    expect(await guard.mayUse('alex'), isTrue);

    await guard.erase();

    expect(await owner.read(), isNull);
    expect(data.hasTraining, isFalse);
    // And whoever signs in next claims an empty phone, without being asked.
    expect(await guard.mayUse('sam'), isTrue);
  });

  test(
    'an account deleted with its copy kept leaves the phone unclaimed',
    () async {
      // The runs stay, and the next account to sign in -- the runner's own new
      // one, most likely -- claims them rather than being told to erase them.
      data.hasTraining = true;
      await owner.write('alex');
      expect(await guard.mayUse('alex'), isTrue);

      await guard.release();

      expect(await owner.read(), isNull);
      expect(data.erased, 0);
      expect(await guard.mayUse('sam'), isTrue);
      expect(await owner.read(), 'sam');
    },
  );
}

class _Training implements LocalTrainingData {
  bool hasTraining = false;
  bool failErase = false;
  int erased = 0;
  int reads = 0;

  @override
  Future<bool> isEmpty() async {
    reads++;
    return !hasTraining;
  }

  @override
  Future<void> eraseAll() async {
    if (failErase) throw StateError('disk');
    erased++;
    hasTraining = false;
  }
}
