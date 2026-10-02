# Landing film: the stills brief

This is the brief for generating the keyframe stills of the landing page film.
It is written to be handed to an image-generating agent as it stands, and read
by Matthew when choosing between results. The idea behind the film is in
[`README.md`](README.md); read that first if you have not.

## What you are making

Five still images of **one fictional athletics stadium**, at five points along
one straight camera path. They are the storyboard for a film that plays as the
visitor scrolls: the camera starts high above the track, comes down to track
level, travels along the home straight into a tunnel under the stand, and comes
out in the weight room beneath it.

A video model will later be given pairs of these stills as its first and last
frame. That only works if every still is plainly the same place, in the same
light, through the same lens. **Consistency between the five matters more than
any one of them being beautiful.**

## Rules for every image

1. **No people, no animals, nothing in motion.** The film is played forwards
   and backwards by scrolling, and a runner would run backwards. The camera is
   the only thing that moves.
2. **No text, logos, signs, flags, sponsor boards or clocks.** The one
   exception is the lane numbers 1 to 8 painted on the track. The scoreboard,
   if visible, is blank and unlit.
3. **Not a real stadium.** No recognisable venue, skyline or landmark.
4. **Photographic, not illustrated.** Fine film grain is welcome. No HDR glow,
   no lens flare, no oversharpening, no tilt-shift blur.
5. **16:9 landscape.** Use the largest landscape size the tool offers. If it
   only offers another shape, compose so that everything that matters sits
   inside the central 16:9 band, and save the image exactly as returned. Do not
   crop, upscale or retouch it.
6. **Leave the named area of each frame empty.** Type and a phone screen are
   laid over these images on the page. Each keyframe below says where.

## The venue

Describe the same place in every prompt. These facts do not change:

- **Track:** eight lanes, a muted oxblood red, slightly damp with a soft matte
  sheen. White lane lines. No puddles and no mirror reflections.
- **Infield:** dark, closely mown grass, almost black in this light.
- **Stand:** one grandstand, along the home straight only. Raw grey concrete
  terraces with dark grey seats, all empty, under a flat cantilevered roof of
  dark steel. Facing the tunnel, the stand is on the **right**.
- **Far side:** no stand. A low dark treeline and misty hills beyond it.
- **Floodlights:** four tall masts, switched off.
- **The tunnel:** the home straight runs on past the bend as a straight chute
  and enters a tunnel in a concrete end wall. The mouth is a plain rectangle
  with square edges, as wide as the eight lanes and about four metres high,
  with a few rows of empty terrace above it. The lane lines run straight into
  it.
- **The weight room:** the tunnel opens into a long room under the stand. Raw
  concrete walls and a concrete ceiling with the underside of the terraces
  visible. Black rubber floor. **The eight white lane lines carry on across the
  floor** and stop at a lifting platform. One steel power rack stands on the
  platform, centred, with a loaded barbell on its hooks. Plates are black and
  bare steel. Light comes from a row of plain strip lights and a high slot
  window letting in the same grey daylight.

## The light and the grade

- **Time:** first light, before sunrise. High, thin, even cloud. No visible
  sun, no shafts of light, no long shadows.
- **Air:** light mist at ground level in the far distance only.
- **Colour:** close to monochrome. Cool neutral greys, low saturation
  everywhere. **The red of the track is the only colour in the picture.**
- **Darks:** the darkest areas sit near `#1A1A1A`, not pure black. The page
  behind the film is that colour, and the image edges should melt into it.
- **Brights:** the brightest thing in any frame is the white of the lane lines
  or the sky near the horizon. Nothing blows out.

## The camera

- One straight path. The camera always looks **along the home straight towards
  the tunnel**. It never turns.
- Ground-level frames: about one metre above the track, on the line between
  lanes 4 and 5, a 35mm lens. The vanishing point is at the centre of the
  frame.
- The overhead frame looks straight down from about sixty metres, with the
  lanes running from the bottom of the frame to the top and the tunnel end at
  the top.

## The five keyframes

Generate them in this order. **K2 comes first** because it shows the most of
the venue. Once Matthew has picked a K2, give that image to the tool as a
reference for all the others, so they inherit its stand, track and light.

### K2. Track level (make this first)

- **Where:** standing on the home straight, about eighty metres from the
  tunnel.
- **Shows:** the lane lines running away to a vanishing point at the centre of
  the frame, where the tunnel mouth sits small and dark. The stand rises on the
  right. The infield, treeline and hills fall away on the left. Sky fills the
  top half.
- **Keep empty:** the sky, especially the upper left. The word RUN and a phone
  screen sit there.
- **Prompt:** *Photograph from one metre above an eight-lane athletics track,
  looking straight down the home straight. Muted oxblood red track, slightly
  damp, white lane lines converging on a small dark rectangular tunnel mouth in
  a concrete end wall at the exact centre of the frame. On the right, an empty
  raw concrete grandstand with dark grey seats under a flat dark steel roof. On
  the left, dark mown infield grass, then a low treeline and misty hills. Four
  unlit floodlight masts. First light before sunrise, thin even cloud, no sun
  visible. Nearly monochrome cool greys, the red track the only colour.
  35mm lens, fine film grain. No people, no text, no logos.*

### K1. Overhead

- **Where:** sixty metres above the same spot, looking straight down.
- **Shows:** the eight lanes as a band of parallel red strips down the right
  third of the frame, running bottom to top, with the painted numbers 1 to 8
  across them. The edge of the stand's roof runs along the far right. The
  infield fills the left two thirds as a flat field of near-black.
- **Keep empty:** the infield. The headline sits on it.
- **Prompt:** *Aerial photograph looking straight down from sixty metres onto
  the home straight of the same athletics stadium as the reference image. Eight
  parallel lanes of muted oxblood red with white lines run from the bottom of
  the frame to the top, in the right third of the frame, with the numbers 1 to
  8 painted across them. The flat dark steel roof of the grandstand runs along
  the right edge. The left two thirds of the frame are dark mown infield grass,
  almost black, flat and empty. Same first light, same nearly monochrome cool
  grey grade, the red track the only colour. Fine film grain. No people, no
  shadows of people, no text other than the lane numbers.*

### K3. The tunnel mouth

- **Where:** on the same line, about ten metres from the tunnel.
- **Shows:** the mouth filling the middle third of the frame, dark inside, with
  the lane lines running into it and fading. Concrete end wall around it, a few
  rows of empty terrace above. A little sky at the very top.
- **Keep empty:** the darkness inside the mouth. A line of text sits on it.
- **Prompt:** *Photograph from one metre above the track, ten metres from the
  tunnel in the reference image. A plain rectangular tunnel mouth in a raw
  concrete wall fills the middle third of the frame, as wide as the eight lanes
  and four metres high, dark inside. The oxblood red lanes and white lines run
  straight into it and fade into the dark. A few rows of empty concrete terrace
  above the mouth, a strip of grey sky at the top. Same light and grade as the
  reference. 35mm lens, vanishing point at the centre. No people, no signs, no
  text.*

### K4. The threshold

- **Where:** inside the tunnel, near its far end.
- **Shows:** black tunnel walls framing a lit rectangle at the centre: the
  weight room seen through the tunnel's exit, with the rack small in the
  middle. The lane lines are just visible on the floor, running towards it.
- **Keep empty:** the dark walls either side. The word LIFT arrives here.
- **Prompt:** *Photograph from inside a dark concrete tunnel, one metre above
  the floor, looking straight ahead to its exit. The walls, floor and ceiling
  are nearly black. At the exact centre, a bright rectangle one third of the
  frame wide shows a concrete weight room beyond, with a steel power rack and
  loaded barbell centred in it. Faint white lane lines on the floor run towards
  the exit. Cool grey light, nearly monochrome. 35mm lens. No people, no text.*

### K5. The weight room

- **Where:** just inside the room, on the same line.
- **Shows:** the room, symmetrical, with the rack and loaded barbell centred on
  its platform. The lane lines cross the black rubber floor and stop at the
  platform. Concrete walls, strip lights, the slot window high on one side.
- **Keep empty:** the wall above and to the left of the rack. The word LIFT and
  a phone screen sit there.
- **Prompt:** *Photograph of a weight room beneath a concrete grandstand, taken
  from one metre above the floor, looking straight ahead, symmetrical. A steel
  power rack with a loaded barbell stands centred on a lifting platform. Black
  rubber floor with eight white lane lines running from the camera to the
  platform, where they stop. Raw concrete walls, a concrete ceiling showing the
  stepped underside of the terraces, a row of plain strip lights, a high slot
  window with grey daylight. Black and bare steel plates. Nearly monochrome
  cool greys, darkest areas near charcoal not pure black. 35mm lens, fine film
  grain. No people, no mirrors, no text, no logos.*

## Where files go

Design source stays out of `public/`, so that nothing unchosen is deployed.

```
web/design/landing/stills/
├─ round-01/            every image from the first round, nothing deleted
│  ├─ k2-a.png
│  ├─ k2-b.png
│  ├─ k2-c.png
│  └─ notes.md          the exact prompt used for each file, and what changed
├─ round-02/
└─ selected/            the one chosen image per keyframe: k1.png … k5.png
```

- Name each file `<keyframe>-<letter>.png`.
- Make **three** variants per keyframe per round. More than that is harder to
  choose between, not easier.
- Record the exact prompt for each file in the round's `notes.md`. A still that
  cannot be regenerated cannot be matched.
- Never overwrite or delete an earlier round.
- **Stop after K2 in round 1** and wait for Matthew to choose. The other four
  depend on it.

Matthew copies each chosen image to `selected/` under its keyframe name. From
there `node tool/film.mjs keys` (run in `web/`) puts them on the page.

## What a good set looks like

Lay the five side by side and check:

- Is the stand on the right in every ground-level frame?
- Are there eight lanes, the same red, in every frame that shows the track?
- Could all five have been taken within the same ten minutes?
- Is the vanishing point at the centre in K2, K3, K4 and K5?
- Is the named area in each frame empty enough to set type on?
- Is there anything in any frame that would look wrong played backwards?

## Later rounds, not now

- **Portrait versions** for phones (9:16), once the landscape set is chosen.
- **A person.** If the film wants a runner or a lifter, they appear in separate
  looping clips, never in the scrolled film.
