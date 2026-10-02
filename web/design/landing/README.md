# The landing page

The home page of mgkfitness.mgkcodes.com is one camera move, played by
scrolling.

It starts high above an athletics track, comes down to track level, travels
along the home straight, goes into the tunnel under the stand and comes out in
the weight room beneath it. **Run arrives where the camera lands on the track.
Lift arrives where it comes out of the tunnel.** One venue holds both apps,
which is the page's whole argument: they are one thing.

The page is designed and the film is made, in both shapes. All five stills are
chosen and on the page, in a wide set and an upright one, and **each film has
its four clips**, so the camera moves on a phone and on a wide screen alike.
[`clips/notes.md`](clips/notes.md) says how each clip came out. Two moves have
faults that are known and left for now, both in both shapes and both under
"Not built yet": the turn to the tunnel, where the red strip changes shape,
and the move into the weight room, where the stills disagree about the room.

| Still | Chosen | Why |
|---|---|---|
| K1 | round 3, `k1-c` | The most infield, so the headline ends short of the first lane |
| K2 | round 2, `k2-b` | The strongest track and the darkest grade; a dry apron |
| K3 | round 3, `k3-c` | The mouth is largest and dead centre |
| K4 | round 3, `k4-c` | Its room has the stepped underside of the terraces, as K5 does |
| K5 | round 3, `k5-c` | The darkest floor, and the terraces overhead say "under the seats" |

And the same five for an upright screen, all from round 4:

| Still | Chosen | Why |
|---|---|---|
| K1p | `k1p-b` | Its lane numbers sit highest, a third of the way down, well clear of the headline |
| K2p | `k2p-c` | The tunnel is furthest in from the right edge, which a phone trims, and the camera stands on a lane line as it does in K2 |
| K3p | `k3p-c` | The roof comes down past the line of text. In `k3p-a` a strip of sky runs through the words |
| K4p | `k4p-c` | The largest opening, with the most of the room through it, and a strip as wide as in the frames either side. `k4p-b`'s is a narrow path |
| K5p | `k5p-c` | The plainest stepped ceiling, with its lights dim and out in the corners. Framed 8% lower, which sets the bar half way down |

## How the film gets made

| Step | Who | What |
|---|---|---|
| 1. Stills | Codex | Five keyframes of one venue, to the brief in [`stills.md`](stills.md) |
| 2. Choice | Matthew | One image per keyframe, copied to `stills/selected/` as `k1.png` … `k5.png`, and `k1p.png` … `k5p.png` for an upright screen |
| 3. On the page | `node tool/film.mjs keys` | The page now crossfades between the stills as it scrolls |
| 4. Clips | Replicate | One short video per move, given two stills as its first and last frame |
| 5. Frames | `node tool/film.mjs frames s1 clip.mp4` | The clip is cut into frames and the page plays them |

Step 3 is worth doing before step 4. It shows the storyboard in place, at full
size, under the real type, for nothing; a clip costs money each time.
[`clips/notes.md`](clips/notes.md) says how a clip is made and records each
one, with its prompt, its cost and what it showed. Read "The retry that cost
$1.41" there before making another.

## Two shapes

The film is kept twice: **wide**, at 16:9, for a screen wider than it is tall,
and **tall**, at 9:16, for an upright one. A wide still cropped to a phone
keeps a slice from its middle and loses the stand and the tunnel, so the tall
film is the same five moments framed again, not the wide ones cropped.

- A tall still is its wide one's name with a `p`: `selected/k2p.png`. The
  brief for them is "The portrait set" in [`stills.md`](stills.md).
- `node tool/film.mjs keys` puts both sets on the page. A clip that is upright
  is taken to be for the tall film.
- An upright screen is shown the tall film as soon as that film has a still.
  A keyframe with no tall still yet is shown its wide one, cropped. A move is
  only ever played from tall frames there: wide frames between two tall stills
  would jump.
- **The tall film needs clips of its own.** A video model is given a first and
  a last frame and returns their shape, so four moves in two shapes is eight
  clips, not four.
- **Both films take every other frame of their clips**, 12 a second, which is
  half the weight and still a frame every dozen pixels of scrolling. The tall
  film's four moves are 214 frames and 9.6 MB. The wide film's are 215 frames
  and 13.3 MB at 1920 wide, which is what a desktop fetches. A visitor whose
  browser asks to save data is sent no frames at all, and sees the
  crossfades.
- On an upright screen the words sit in the top third of the frame and the
  phone rises over the bottom of it, so what is seen clean is a band across
  the middle. The brief says where each thing is, measured from the page.
- **A phone is often a short screen.** With its browser's bars showing, an
  iPhone gives the page about 390 by 664, and an app's own browser much the
  same. The same type takes more of that, so on an upright screen the names
  and captions are sized against the height as well as the width.
- **A still can be framed.** `stills/selected/framing.json` names a share of a
  still's height to cut from its top or bottom before it is cropped to shape,
  which moves its subject to where the page leaves room. The chosen image is
  left as it was made. K5p is cut 8% at the bottom, so the bar sits just above
  the phone on a short screen and a tall one. **A clip for the tall film is
  made from the framed still**, or its last frame will not match the page's.
- **Words that cross a busy frame bring their own ground.** On an upright
  screen the headline lies over lanes from edge to edge, and the line in the
  tunnel reaches a strip of sky on a short one. Each has a shade of the page's
  colour behind it that leaves when it does.

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
- **A hold is its still.** A clip's first and last frames are its stills as a
  video model remade them: near enough to pass for them, and softer. So where
  the camera rests the page shows the still, and eases out of the frame the
  camera arrived on and into the one it leaves on over a little scrolling at
  either end.
- **A clip is cut to the scroll, not to the clock.** A video model paces a
  move as it likes, and one that creeps and then rushes scrubs badly. What is
  done to a clip as it is cut, to even it out or to dissolve a jump inside it,
  is in `clips/edits.json`, and the clip is left as it was made.
- **The screens are real.** The phones show captures of the apps, not drawings
  of them, three per app, changing as the hold is scrolled. Run's are the
  screens its store pictures are made from (`test/plates/store.dart`, 1290 by
  2796). Lift's are from its review captures, which have no status bar; they
  want retaking the way Run's were once Lift has store screens of its own.
- **The phone is the store pictures' phone.** The screens sit in a drawn frame
  with an iPhone's proportions, its camera island, buttons and status bar,
  measure for measure the one Run's store pictures use, so the site and the
  listing show one device. It is drawn rather than Apple's own product image,
  for the reason the store pictures give: a listing may not show another
  company's product as though it endorsed the app. `device.tsx` has it.
- **The words are the listings' words.** Every line over the film, and every
  line under "Tracking is free", is one the store listings already make, and
  each says whether it is free or the subscription. The page may not promise
  what a listing may not: see "What the app may not claim" in Run's
  `app-store-listing.md`.
- **The case for the coach answers troubles, and promises nothing.** Under the
  film, the page says why somebody would pay: a personal trainer's cost and
  hours, a plan written for somebody else, a missed week, nobody to ask. Each
  trouble is answered with something a listing already says the coach does,
  never with a result. The prices are the stores' own, £0.99 and £2.99 a month
  (Run's ADR-0029), given as UK prices, and the page says that Run and Lift are
  subscribed to separately, because they are (`core.entitlements` holds a row
  per app).
- **The page shades the film.** The stills' sky is too light for white type
  (about 2.8 to 1), so the stage lays the page's own colour over the top and
  bottom of the frame. That is done once in `landing.css`, not baked into the
  stills, so every frame gets the same treatment.
- **The phone stays clear of the tunnel.** At track level the players' tunnel
  is on the right of the frame and is where the film goes next, so the phone
  sits left of it.
- **Reduced motion gets cuts.** A visitor who has asked for less motion sees
  the stills change, not the camera travel.
- **Run and Lift in the bar are places in the film.** Choosing one scrolls the
  page there at the film's own speed, so the film is watched on the way and
  not skipped. Anything the visitor does stops it. They are ordinary links to
  `#run` and `#lift` underneath.
- **It is MGKFitness first.** The page opens on the suite's name, set as its
  apps' names are, and says what is true of the two together: one account, one
  design, free to track. The suite's own mark stands before its name in the
  bar: the apps' two chevrons, heading between Run's right and Lift's up. A
  phone too narrow for both is shown the name, and a narrower one the mark.

## Not built yet

- **Anything that emails the waiting list.** The form saves an address, says
  what it is for and how to come off, and links to the website's privacy
  notice at `/privacy`. Nothing sends the email yet, and the notice promises
  to name whoever does before it is sent, and to delete the list once both
  apps are live.
- **Each app showing the other's training.** The page marks it as coming,
  and it is planned. `core.activities` holds every run and workout so that it
  can be done, and neither app reads it yet, so nothing on the page says that
  it is. Run's privacy policy already describes the shared feed; Lift's does
  not, and will need to before Lift shows a run.
- **The store links, the accounts to follow and the public repository.** All
  three are shown as coming, and all are turned on in
  `app/(landing)/links.ts`. The accounts are not a section of the page: they
  are their own marks in the bar, greyed and not links until each has an
  address. [`docs/going-public.md`](../../../docs/going-public.md) is the list
  for the day the repository opens.
- **The turn to the tunnel, made again.** In both films the red strip changes
  shape under the camera as it turns, so the move does not read as one shot.
  It is known and left for now. A prompt did not cure it in the wide film;
  `clips/notes.md` has why it happens and what is left to try.
- **One weight room.** K4's far end and K5 are two different rooms, in both
  sets: a bright hall with slanting columns, and the dark room the film ends
  in. A video model given both walks into the first and cuts to the second.
  Both films dissolve across that cut, which hides the jump and not the
  difference. The cure is a K4, and a K4p, whose far end is K5's room, made
  from K5, and then the tunnel move and the move into the room made again.
- **Where the frames live.** `tool/film.mjs` writes them into `public/film/`,
  which is committed. The upright film's frames are 9.6 MB and the wide film's
  18 MB, in its two widths; if that is too much for the repository they move
  to a storage bucket. The clips they are cut from are several megabytes each
  and are not committed at all: see `clips/notes.md`.
- **A lighter film.** 9.6 MB is what a phone fetches if it stays on the page,
  and 13.3 MB a desktop, every eighth frame of each move first and then the
  gaps. Narrower frames would halve either, at some cost in sharpness while
  the camera is moving.
- **The page is not indexed.** `robots` is off in the landing layout until the
  film and the list are real.
