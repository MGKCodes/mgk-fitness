# MGKFitness: Lift 2.0.0: the test sheet

Fill this in on the phone, with the build in your hand. Tick what passes, write
a line where it does not, and hand the whole thing back. A failed row with two
words of context is worth more than a green sheet.

**Tick only what you actually saw.** An untested row left blank is useful; an
assumed pass is not.

Rewritten 1 October 2026 for the redesigned app. The sheet it replaces was
written for the August build and described screens that no longer exist: an
intake that asked age, height and weight, no terms or privacy links, photos
that did not sync, and a hand-written `insert` to unlock the coach. Codes like
`W6` are plates on the
[Lift Screen Board](https://claude.ai/artifact/UZKDFbA8qht1Nj9TQ3dQB1).

## Before you start

**1. Use build 41 or later**, not build 32. Build 32 predates the redesign
and Sign in with Apple and Google, so nothing below describes it. Build 41,
from 1 October, is the first this sheet describes. See
[submission-week.md](submission-week.md), step 2.

**2. Two accounts.** One left free, to see the offer and to buy. One entitled
without paying, so the paid half can be tested before the store products
exist. To entitle it, run this once in the Supabase SQL editor:

```sql
select core.grant_entitlement('you@example.com', 'lift');
```

It grants `paid` and `active`. `core.revoke_entitlement('you@example.com',
'lift')` takes it back.

**3. Know which install you are**, and say which you did:

- **Upgrade:** a phone with Liftio 1.4.0 on it. This is the path that matters,
  because the App Store delivers 2.0.0 to those people as an update.
- **Fresh:** a phone that has never had Liftio. Every Android phone is this.

## Known gaps: do not report these

Listed in [submission-week.md](submission-week.md) under *Shipping with these,
knowingly*. The ones you will meet on this sheet:

- Deleting an account **on Android** does not revoke Apple's tokens.
- The summary's C opens the coach as it does anywhere, not on that session.
- Plan's week shows the plan's own counts, not what you have done against it.
- A movement you have never logged shows no weight. Sets and reps come from the
  plan; weights come from your log.
- Progress photos in a browser preview are grey tiles. On a phone they are not.

---

## A. Install and first run

| # | Step | Expected | ✓ |
|---|---|---|---|
| A1 | Install and open | The launch plays: the mark dips, drives up, and LIFT rises under it, with MGKFitness beneath. About two seconds, then Track, usable, with no sign-in asked for | ☐ |
| A1a | Leave the app and come back | No launch the second time; you are where you left off | ☐ |
| A1b | Tap between Track, Plan and Profile | Each tab shifts in and fades rather than cutting, and the bar's highlight slides to the tab you chose | ☐ |
| A1c | *(Optional)* Settings › Accessibility › Reduce Motion on, then a cold start | No launch animation, and tabs change at once | ☐ |
| A2 | *(Upgrade)* Open on a phone that had 1.4.0 | Opens; does not crash on the old app's data | ☐ |
| A3 | *(Upgrade)* Sign in as the 1.4.0 account and look for your history | **Never seen either way.** Write down exactly what arrives: sessions, dates, weights, photos | ☐ |
| A4 | The name under the icon | `Lift` | ☐ |
| A5 | *(iOS)* The TestFlight page | Offered for iPhone only, not iPad | ☐ |
| A6 | Force-quit and reopen | Back where you were; a running session is still running | ☐ |

## B. Signing in (S1, S3)

Do the whole section on an iPhone and on an Android phone.

| # | Step | Expected | ✓ |
|---|---|---|---|
| B1 | Profile › the gear › Sign in, on the account card | The sign-in screen: Apple, Google, then Continue with email | ☐ |
| B2 | Continue with Apple | Signed in. On Android it goes out to a browser and comes back to the app | ☐ |
| B3 | Continue with Apple, choosing Hide My Email | A separate account, as the line under the button says | ☐ |
| B4 | Continue with Google | Signed in, with no password | ☐ |
| B5 | Continue with email › create an account | "Check your email and follow the link, then sign in." The email arrives from MGKFitness, in the inbox and not spam; its link confirms | ☐ |
| B6 | Sign in before confirming | Refused in words, not a raw code | ☐ |
| B7 | A wrong password | Does not say which half was wrong | ☐ |
| B8 | Forgot your password? | The email arrives; its link opens the reset page; the new password works and the old one does not | ☐ |
| B9 | *(Upgrade)* Sign in with Apple as an account made in Liftio 1.x | The same account, with its history | ☐ |
| B10 | Sign out, sign in as a **different** account on the same phone | Asked first: erase this phone's training and start clean, or sign out and leave it | ☐ |
| B11 | *(Only if Run is on the phone)* Sign into Run with the same account | One person in both apps | ☐ |
| B12 | Kill the app while signed in, reopen | Still signed in | ☐ |

## C. Logging a workout: the free half (T1 to T9, W1 to W26)

Signed out is fine for all of this. It is what Liftio's users already had, so
it has to be right.

| # | Step | Expected | ✓ |
|---|---|---|---|
| C1 | First open, nothing saved | Track says "Ready when you are", with the week and the last session drawn empty (dashes, no noughts) | ☐ |
| C2 | Start a session | Opens Your workouts: a blank session first, then three starters (Full Body, Upper / Lower, PPL). No photographs | ☐ |
| C2a | Add a starter | Added in one tap, with Undo | ☐ |
| C3 | Start on a saved workout | The session opens filled: every set with its reps and last time's weight. Nothing is pre-ticked | ☐ |
| C4 | Start a session › Blank session | Opens with the clock running | ☐ |
| C4a | Back on Track after finishing | Today names the session with when it ended and how long it took; This week has a dot and the start time on today | ☐ |
| C4b | The next day | Last session shows it: name, day and time, length, sets, movements. Tapping it opens its page | ☐ |
| C5 | + Add, then search `curl bicep`, `db press`, and a word with one typo | Each finds its movements; the typo ranks below a clean match | ☐ |
| C6 | Narrow by a muscle chip and an equipment chip | The list narrows, with search or without | ☐ |
| C7 | Tick a set | Saved at once; the rest dock rises with the timer | ☐ |
| C8 | Let the rest run out | Counts up past zero | ☐ |
| C9 | Tick a set, lock the phone | A notification at the rest's end, naming the next set. Unlock: no second buzz | ☐ |
| C10 | Change one movement's rest length | It keeps its own length next time | ☐ |
| C11 | Tap a set's number | Cycles the set type; a warm-up is left out of volume | ☐ |
| C12 | The swap icon, on the free account | The picker in replace mode; logged sets stay under the old name | ☐ |
| C13 | Reorder movements, at the foot of the list | Drag by the handle; the session follows | ☐ |
| C14 | Beat a movement's best estimate with a ticked set | The C opens, says the new best, and closes. Matching a best says nothing | ☐ |
| C15 | Back out of the session | The Today card names it and how far in, and its button reads Resume session | ☐ |
| C16 | With that session open | Track offers nothing but Resume; no second session can be started over it | ☐ |
| C17 | Leave a session open overnight | Still offered the next day; nothing ended it for you | ☐ |
| C18 | Finish, from a saved workout with a movement added or removed | The sheet asks once, "Save to … for next time?", listing the change, switched on | ☐ |
| C19 | Finish with only set counts or order changed | Does not ask | ☐ |
| C20 | Finish a blank session | "Save as a workout", off; a name field only when switched on | ☐ |
| C21 | The summary | Volume leading, on glass; one exit, Done; back does not return to the session | ☐ |
| C22 | Finish with no signal | A pill at the top says it is saved on this phone. Back online, it goes | ☐ |
| C23 | Discard a session | Nothing is written | ☐ |
| C24 | A session past one hour | The clock reads `1:02:14` without clipping | ☐ |

## D. Your workouts (W2, W3, W17, W24)

| # | Step | Expected | ✓ |
|---|---|---|---|
| D1 | Track › Start a session | Solid rows on a plain dark background, easy to read: Blank session, then each workout with Start and a … | ☐ |
| D2 | Tap a row | Opens in place to every movement, sets × reps | ☐ |
| D3 | … › Edit | The editor: set counts, rep targets, order, remove. No weights | ☐ |
| D4 | … › Duplicate, then Delete | A copy under a free name; delete removes it | ☐ |

## E. The offer and paying (P1, P8, P9)

On the **free** account. Needs the store products
([store-setup.md](store-setup.md) steps 1 to 5) and a sandbox tester.

| # | Step | Expected | ✓ |
|---|---|---|---|
| E1 | Tap the C on Track, on Plan, on Profile and in a session | The same sales screen each time | ☐ |
| E2 | Plan › Start coaching; Photos › Unlock photos | The same screen | ☐ |
| E3 | Read it | Two tiers, each with the store's own price; renewal terms, Terms, Privacy and Restore at the foot | ☐ |
| E4 | Signed out, choose a tier | Asks for an account first, then goes on to the store. Backing out buys nothing | ☐ |
| E5 | Buy Coach | The screen you came from unlocks, without restarting the app | ☐ |
| E6 | Move up to Premium Coach | The store treats it as an upgrade of the same subscription, not a second one. Write down when it takes effect | ☐ |
| E7 | Reinstall, sign in, Settings › the account card › Restore purchases | The subscription comes back | ☐ |
| E8 | Restore on an account with nothing bought | Says there is nothing to restore; not an error | ☐ |
| E9 | Cancel in the store's settings | Access stays until the period ends | ☐ |
| E10 | *(Only if Run is on the phone)* Open Run on the same account after buying in Lift | Run is not unlocked by it; each app has its own subscription | ☐ |

## F. The plan (P2, P5, P6, Q1 to Q11)

On an entitled account.

| # | Step | Expected | ✓ |
|---|---|---|---|
| F1 | Plan, with no plan yet | Three steps saying what happens next, and Build a plan | ☐ |
| F2 | Walk the questions | Four: days, equipment, injuries, goal. One at a time; an option or your own words | ☐ |
| F3 | Build my plan | A plan arrives, with a name and why this shape for you | ☐ |
| F4 | Count the training days | They match the days you gave | ☐ |
| F5 | Plan on a training day | The week first; today links to Track. Nothing here starts a workout | ☐ |
| F6 | Track on that day | The Today card is the day: its name, a count of movements, a button named for it, and Start something else under it. This week rings the plan's days and says what is next | ☐ |
| F6a | Track on a rest day | "Rest day", when the next session is, and Start a session anyway, outlined | ☐ |
| F7 | Start it | Filled with the day's movements; nothing pre-ticked | ☐ |
| F8 | Another day › Do it today | Track shows it as today's, "moved from …", until finished or the day ends | ☐ |
| F9 | Plan on a rest day | Says so. Nothing owed | ☐ |
| F10 | Aeroplane mode, reopen | Today's session is still on Track | ☐ |
| F11 | Finish a planned session | The coach asks how it felt; your answer shapes the next one | ☐ |

## G. The coach (C1 to C11)

| # | Step | Expected | ✓ |
|---|---|---|---|
| G1 | Tap the C | A sheet over where you were, which you can still see | ☐ |
| G2 | Ask a real question about your training | An answer that has read your log | ☐ |
| G3 | Close it, reopen within half an hour | The same conversation | ☐ |
| G4 | Reopen after more than half an hour | A new one; the old one is under the history control, read-only | ☐ |
| G5 | Ask about pain that has lasted weeks | Declines to diagnose and says to see somebody | ☐ |
| G6 | Mid-session, the swap icon | The coach proposes a replacement that exists in the catalogue | ☐ |
| G7 | Send messages until the limit | Names the limit in plain words | ☐ |
| G8 | The info mark in the coach's top bar | How your coach uses AI | ☐ |
| G9 | Settings › switch the coach off | The C leaves every screen, and Plan cannot build | ☐ |
| G10 | Settings › Coach | What it remembers, in sentences; it can be cleared | ☐ |

## H. Profile, history and photos (G1 to G14)

| # | Step | Expected | ✓ |
|---|---|---|---|
| H1 | Profile | Six numbers that match what you logged; the last five sessions; See all | ☐ |
| H2 | Profile on a new account | Dashes, not zeros | ☐ |
| H3 | See all › a session › Edit session | The session screen on an old session: no clock, no rest. Done saves | ☐ |
| H4 | Delete a past session | Gone from every total at once, with Undo | ☐ |
| H5 | Tap a movement's name, in a session, a summary, the history and Profile | Its own screen: best, the estimate over time, its sessions | ☐ |
| H6 | A bodyweight movement's screen | No estimate, and a line saying why | ☐ |
| H7 | Progress photos › add (entitled) | Asks camera or gallery; the permission prompt gives a reason | ☐ |
| H8 | Take one, then open its pose | One a week, missed weeks left as gaps | ☐ |
| H9 | Play the sequence | Plays, stops at the end; the scrubber stops playback | ☐ |
| H10 | Delete a photo | Asks, bluntly; it is gone | ☐ |
| H11 | Sign in on a second install | The photos arrive; the deleted one does not come back | ☐ |
| H12 | Photos after the subscription lapses | No camera, but every photo still readable and deletable | ☐ |

## I. Settings, backup and leaving (A1 to A12, L1 to L6)

| # | Step | Expected | ✓ |
|---|---|---|---|
| I1 | Settings, signed out | The account card says what is on this phone only | ☐ |
| I2 | Switch kg to lb | Every weight converts, everywhere, at once | ☐ |
| I3 | Aeroplane mode, log a session, come back online | Backs up without being asked | ☐ |
| I4 | The account card › Sync now | A time, "3 min ago", not a status word | ☐ |
| I5 | Sign in on a second phone | The same history arrives | ☐ |
| I6 | Sign out | Training stays on the phone | ☐ |
| I7 | Privacy & legal | Terms, privacy and the AI disclosure open with no signal | ☐ |
| I8 | Delete account › Delete my Lift data | Lift's data goes, progress photos included; the login stays if the account has runs | ☐ |
| I9 | Delete account › Delete my whole MGKFitness account, made with Apple, on iPhone | Apple asks you to confirm. Closing Apple's sheet deletes nothing | ☐ |
| I10 | Sign in again afterwards | A new account | ☐ |
| I11 | Text size at the phone's largest setting | Nothing overflows or clips. Write down every screen that does | ☐ |

---

## What to send back

1. This sheet, ticked, with a line against anything that failed.
2. Which phone, which install path, and which build number.
3. **The answer to A3:** what a 1.4.0 lifter keeps. It decides whether 2.0.0
   can go to the existing listing at all.
4. Anything that felt wrong but still passed. Those are the ones worth arguing
   about.
