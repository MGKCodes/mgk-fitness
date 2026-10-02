# Landing film: the stills brief

This is the brief for generating the keyframe stills of the landing page film.
It is written to be handed to an image-generating agent as it stands, and read
by Matthew when choosing between results. The idea behind the film is in
[`README.md`](README.md); read that first if you have not.

## What you are making

Five still images of **one fictional athletics stadium**, at five points along
one camera path. They are the storyboard for a film that plays as the visitor
scrolls: the camera starts high above the track, comes down to track level,
travels along the home straight, swings into the players' tunnel in the base of
the grandstand and comes out in the weight room under the seats.

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
- **Infield:** closely mown grass so dark it is almost black. **Not green.**
- **Stand:** one grandstand, along the home straight only. Raw grey concrete
  terraces with dark grey seats, all empty, under a flat cantilevered roof of
  dark steel. Looking along the straight, the stand is on the **right**. A dry
  concrete apron a few metres wide lies between the track and the stand's base
  wall.
- **The players' tunnel:** the way into the stand. A plain rectangular opening
  with square edges in the stand's concrete base wall, directly beneath the
  seats, about four metres wide and three high, dark inside. It is on the
  right, about forty metres ahead of the track-level camera. **A strip of the
  same red track surface, two metres wide, leaves the edge of the track,
  crosses the apron and runs into the tunnel.**
- **Far end of the straight:** the track bends away to the left. Beyond it, a
  low concrete wall, a dark treeline and misty hills. No tunnel and no opening
  there.
- **Far side:** no stand. The same treeline and hills.
- **Floodlights:** four tall masts, switched off.
- **The weight room:** the tunnel is short and opens into a long room under the
  stand's seats, as a changing room would be. Raw concrete walls. The ceiling
  is the stepped underside of the terraces above. Black rubber floor. **The red
  strip carries on along the tunnel floor and across the room**, and ends at a
  lifting platform. One steel power rack stands on the platform, centred, with
  a loaded barbell on its hooks. Plates are black and bare steel. Light comes
  from a row of plain strip lights and a high slot window letting in the same
  grey daylight.

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

- About one metre above the ground in every frame but the overhead. A 35mm
  lens.
- **On the track it looks along the home straight**, on the line between lanes
  4 and 5, with the lanes' vanishing point at the centre of the frame.
- **Then it leaves the track.** Between K2 and K3 it moves forward and swings
  right in one smooth arc, following the red strip, until it faces the tunnel
  square on. From K3 onwards it travels in a straight line along the strip,
  with the tunnel's vanishing point at the centre of the frame.
- The overhead frame looks straight down from about sixty metres, with the
  lanes running from the bottom of the frame to the top and the stand's roof
  along the right edge.

## What round 1 taught

Round 1 made three K2 frames with the tunnel at the far end of the straight.
They held the venue well between them, which was the main thing to find out.
Three things change for round 2:

- **The tunnel moves into the stand.** At the end of the straight it sat in a
  low wall with nothing behind it but trees, so there was nowhere for a weight
  room to be. Weight rooms and changing rooms are under the seats.
- **The grade is `k2-b`'s.** Its grass is nearly black and the whole frame is
  close to monochrome. In `k2-a` and `k2-c` the grass is plainly green.
- **The track is `k2-a`'s.** The red fills the bottom third or more of the
  frame and the lanes converge hard. In `k2-b` the track is a thin band.

The apron beside the track was also wet and reflective in all three. It should
be dry and matte.

## The five keyframes

Generate them in this order. **K2 comes first** because it shows the most of
the venue. Once Matthew has picked a K2, give that image to the tool as a
reference for all the others, so they inherit its stand, track and light.

### K2. Track level (make this first)

- **Where:** standing on the home straight, the stand alongside on the right.
- **Shows:** the lane lines running away to a vanishing point at the centre of
  the frame, where the track bends off to the left. The red fills the bottom
  third of the frame or more. The stand rises on the right, and in its base
  wall, about forty metres ahead, the dark rectangle of the players' tunnel,
  with the red strip leaving the track and crossing the apron to it. The
  infield, treeline and hills fall away on the left. Sky fills the top half.
- **Keep empty:** the sky, especially the upper left. The word RUN and a phone
  screen sit there.
- **Prompt:** *Photograph from one metre above an eight-lane athletics track,
  looking straight along the home straight. Muted oxblood red track, slightly
  damp with a matte sheen, white lane lines converging to a vanishing point at
  the centre of the frame, where the track bends away to the left. The red
  track fills the bottom third of the frame. On the right, an empty raw
  concrete grandstand with dark grey seats under a flat cantilevered dark steel
  roof. In the grandstand's concrete base wall, about forty metres ahead, a
  plain dark rectangular players' tunnel four metres wide, directly beneath the
  seats. A two-metre strip of the same red surface leaves the track, crosses a
  dry matte concrete apron and runs into the tunnel. On the left, closely mown
  infield grass so dark it is almost black, then a low treeline and misty
  hills. Four unlit floodlight masts. First light before sunrise, thin even
  cloud, no sun visible. Nearly monochrome cool greys, the red track the only
  colour, no green. 35mm lens, fine film grain. No people, no text, no logos.*

### K1. Overhead

- **Where:** sixty metres above the same spot, looking straight down.
- **Shows:** the eight lanes as a band of parallel red strips down the right
  third of the frame, running bottom to top, with the painted numbers 1 to 8
  across them. To their right, the grey apron, crossed by the red strip, and
  then the edge of the stand's roof along the far right. The infield fills the
  left two thirds as a flat field of near-black.
- **Keep empty:** the infield. The headline sits on it.
- **Prompt:** *Aerial photograph looking straight down from sixty metres onto
  the home straight of the same athletics stadium as the reference image. Eight
  parallel lanes of muted oxblood red with white lines run from the bottom of
  the frame to the top, in the right third of the frame, with the numbers 1 to
  8 painted across them. To the right of the lanes, a strip of dry grey
  concrete apron, crossed by one two-metre band of the same red surface leading
  right. The flat dark steel roof of the grandstand runs along the right edge.
  The left two thirds of the frame are closely mown infield grass, almost
  black, flat and empty. Same first light, same nearly monochrome cool grey
  grade, the red the only colour. Fine film grain. No people, no shadows of
  people, no text other than the lane numbers.*

### K3. The tunnel mouth

- **Where:** on the red strip, on the apron, about eight metres from the
  tunnel, facing it square on. The track is behind the camera.
- **Shows:** the tunnel mouth filling the middle third of the frame, dark
  inside, with the red strip running into it and fading. The stand's concrete
  base wall either side. Rows of empty seats rising above the mouth, and the
  underside of the roof at the very top.
- **Keep empty:** the darkness inside the mouth. A line of text sits on it.
- **Prompt:** *Photograph from one metre above the ground, eight metres from
  the players' tunnel in the reference image, facing it square on. A plain
  rectangular tunnel mouth in the raw concrete base wall of a grandstand fills
  the middle third of the frame, dark inside. A two-metre strip of muted
  oxblood red track surface runs from the camera straight into it and fades
  into the dark, with dry matte concrete either side. Rows of empty dark grey
  seats rise above the mouth, and the underside of a dark steel roof crosses
  the top of the frame. Same light and grade as the reference. 35mm lens,
  vanishing point at the centre. No people, no signs, no text.*

### K4. The threshold

- **Where:** inside the tunnel, near its far end.
- **Shows:** black tunnel walls framing a lit rectangle at the centre: the
  weight room seen through the tunnel's exit, with the rack small in the
  middle. The red strip is just visible on the floor, running towards it.
- **Keep empty:** the dark walls either side. The word LIFT arrives here.
- **Prompt:** *Photograph from inside a short dark concrete tunnel, one metre
  above the floor, looking straight ahead to its exit. The walls, floor and
  ceiling are nearly black. At the exact centre, a bright rectangle one third
  of the frame wide shows a concrete weight room beyond, with a steel power
  rack and loaded barbell centred in it. A faint strip of muted red track
  surface on the floor runs towards the exit. Cool grey light, nearly
  monochrome. 35mm lens. No people, no text.*

### K5. The weight room

- **Where:** just inside the room, on the same line.
- **Shows:** the room, symmetrical, with the rack and loaded barbell centred on
  its platform. The red strip crosses the black rubber floor and ends at the
  platform. Concrete walls, the stepped underside of the terraces overhead,
  strip lights, the slot window high on one side.
- **Keep empty:** the wall above and to the left of the rack. The word LIFT and
  a phone screen sit there.
- **Prompt:** *Photograph of a weight room beneath the seats of a concrete
  grandstand, taken from one metre above the floor, looking straight ahead,
  symmetrical. A steel power rack with a loaded barbell stands centred on a
  lifting platform. Black rubber floor with one two-metre strip of muted
  oxblood red track surface running from the camera to the platform, where it
  ends. Raw concrete walls, a concrete ceiling that is the stepped underside of
  the terraces, a row of plain strip lights, a high slot window with grey
  daylight. Black and bare steel plates. Nearly monochrome cool greys, the red
  strip the only colour, darkest areas near charcoal not pure black. 35mm lens,
  fine film grain. No people, no mirrors, no text, no logos.*

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
- **Stop after K2** and wait for Matthew to choose. The other four depend on
  it.

Matthew copies each chosen image to `selected/` under its keyframe name. From
there `node tool/film.mjs keys` (run in `web/`) puts them on the page.

## What a good set looks like

Lay the five side by side and check:

- Is the stand on the right in K1 and K2, with the tunnel in its base?
- Are there eight lanes, the same red, in every frame that shows the track?
- Is the red strip in all five, leading the same way?
- Is the grass near black, and is the red the only colour?
- Could all five have been taken within the same ten minutes?
- Is the vanishing point at the centre in K2, K3, K4 and K5?
- Is the named area in each frame empty enough to set type on?
- Is there anything in any frame that would look wrong played backwards?

## Later rounds, not now

- **Portrait versions** for phones (9:16), once the landscape set is chosen.
- **A person.** If the film wants a runner or a lifter, they appear in separate
  looping clips, never in the scrolled film.
