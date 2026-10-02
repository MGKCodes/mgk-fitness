# The landing page

The home page of mgkfitness.mgkcodes.com is one camera move, played by
scrolling.

It starts high above an athletics track, comes down to track level, travels
along the home straight, goes into the tunnel under the stand and comes out in
the weight room beneath it. **Run arrives where the camera lands on the track.
Lift arrives where it comes out of the tunnel.** One venue holds both apps,
which is the page's whole argument: they are one thing.

The page is designed and the film is not made yet. All five stills are chosen
and on the page, which crossfades between them as it scrolls. The clips that
turn those crossfades into a moving camera are the next step.

| Still | Chosen | Why |
|---|---|---|
| K1 | round 3, `k1-c` | The most infield, so the headline ends short of the first lane |
| K2 | round 2, `k2-b` | The strongest track and the darkest grade; a dry apron |
| K3 | round 3, `k3-c` | The mouth is largest and dead centre |
| K4 | round 3, `k4-c` | Its room has the stepped underside of the terraces, as K5 does |
| K5 | round 3, `k5-c` | The darkest floor, and the terraces overhead say "under the seats" |

## How the film gets made

| Step | Who | What |
|---|---|---|
| 1. Stills | Codex | Five keyframes of one venue, to the brief in [`stills.md`](stills.md) |
| 2. Choice | Matthew | One image per keyframe, copied to `stills/selected/` as `k1.png` … `k5.png` |
| 3. On the page | `node tool/film.mjs keys` | The page now crossfades between the stills as it scrolls |
| 4. Clips | Replicate | One short video per move, given two stills as its first and last frame |
| 5. Frames | `node tool/film.mjs frames s1 clip.mp4` | The clip is cut into frames and the page plays them |

Step 3 is worth doing before step 4. It shows the storyboard in place, at full
size, under the real type, for nothing; a clip costs money each time.

## The shots

Five stills, four moves between them, and three places the camera rests.

| Shot | Kind | Stills | On the page |
|---|---|---|---|
| `above` | hold | K1 | The headline, over the infield |
| `s1` | move | K1 to K2 | Down to the track |
| `track` | hold | K2 | RUN, and Run's screen |
| `s2` | move | K2 to K3 | Along the straight, then round to face the players' tunnel in the stand |
| `s3` | move | K3 to K4 | Through the tunnel. The dark is where one line of text sits |
| `s4` | move | K4 to K5 | Out into the weight room |
| `room` | hold | K5 | LIFT, and Lift's screen |

How long each takes to scroll is a number in
[`app/(landing)/storyboard.ts`](../../app/(landing)/storyboard.ts), and nowhere
else.

## Rules the film is made to

- **The venue is empty.** Scrolling plays the film backwards as well as
  forwards. With nobody in it, the camera is the only thing that moves and it
  reads the same both ways.
- **The tunnel is the join.** The clips are made separately, and the dark hides
  where one ends and the next begins.
- **The screens are real.** The phones show captures of the apps, not drawings
  of them, three per app, changing as the hold is scrolled. Run's are the
  screens its store pictures are made from (`test/plates/store.dart`, 1290 by
  2796). Lift's are from its review captures, which have no status bar; they
  want retaking the way Run's were once Lift has store screens of its own.
- **The words are the listings' words.** Every line over the film, and every
  line under "Tracking is free", is one the store listings already make, and
  each says whether it is free or the subscription. The page may not promise
  what a listing may not: see "What the app may not claim" in Run's
  `app-store-listing.md`.
- **The page shades the film.** The stills' sky is too light for white type
  (about 2.8 to 1), so the stage lays the page's own colour over the top and
  bottom of the frame. That is done once in `landing.css`, not baked into the
  stills, so every frame gets the same treatment.
- **The phone stays clear of the tunnel.** At track level the players' tunnel
  is on the right of the frame and is where the film goes next, so the phone
  sits left of it.
- **Reduced motion gets cuts.** A visitor who has asked for less motion sees
  the stills change, not the camera travel.

## Not built yet

- **The waiting list does not save anything.** It needs a table, wording that
  says what the address is for, and a line in both apps' privacy policies. The
  form says the list is not open until then.
- **The headline is a stand-in.** "Two apps. One coach." and the sentence under
  it come from the old home page, not from a listing.
- **A portrait film for phones.** The landscape stills crop badly to a tall
  screen; `stills.md` leaves the portrait set for a later round.
- **Where the frames live.** `tool/film.mjs` writes them into `public/film/`,
  which is committed. Four moves at two sizes is some tens of megabytes; if
  that is too much for the repository they move to a storage bucket.
- **The page is not indexed.** `robots` is off in the landing layout until the
  film and the list are real.
