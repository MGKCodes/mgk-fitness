# The clips

One short video per move, made by a video model from two stills: the move's
first frame and its last. `node tool/film.mjs frames <move> <clip>` cuts one
into the frames the page plays.

The videos are not committed. Each is several megabytes and the page uses only
the frames cut from them, so they stay in this folder on the disk they were
made on, as the stills' rounds do. This file records each one, so that a clip
can be made again the same way.

## How a clip is made

- **Model:** `vidu/q3-pro` on Replicate. It takes `start_image` and
  `end_image` and makes the move between them. It is billed per second of
  video: $0.07 at 540p, $0.15 at 720p, $0.16 at 1080p (read from the model's
  own page on 2 October 2026; read it again before quoting).
- **Turn `audio` off.** It is on by default, and the film has no sound.
- **The two frames are the page's stills**, cropped as `tool/film.mjs` crops
  them, and framed where `stills/selected/framing.json` frames one. The clip
  then begins and ends on exactly what the page holds on.
- **Replicate fetches the frames from a URL**, and they exist only on the
  machine they were made on. They are served from a scratch folder holding
  those two files, through a temporary tunnel (`cloudflared tunnel --url`),
  which is closed as soon as the clip is made.
- **The output is deleted from Replicate after an hour**, so it is downloaded
  at once.
- **A test is 540p and a final is 1080p.** The same seed at another size is
  another roll, so a good test proves the model and the prompt. It does not
  preview the final.

## What has been made

### `s3p-test-540p.mp4`, 2 October 2026

| | |
|---|---|
| Move | `s3`, upright: the tunnel mouth (K3p) to the threshold (K4p) |
| Settings | `vidu/q3-pro`, 540p, 5 seconds, audio off, seed 29 |
| Cost | $0.35 (5.04 seconds at $0.07) |
| Prediction | `s9jzhzccx9rmr0d0znk957m9s8`, 55 seconds to make |
| Returned | 540 by 960, 24 frames a second, 121 frames, 3.8 MB, no sound |

Prompt:

> Slow, steady forward dolly shot. The camera glides straight ahead at walking
> pace along the red running-track strip, through the concrete tunnel mouth
> and on down the dark concrete tunnel, towards the lit weight room at its far
> end. The camera stays level, one metre above the ground, pointing straight
> ahead: no pan, no tilt, no zoom, no shake. The scene is empty and still: no
> people, nothing moves except the camera. Overcast, cool, nearly monochrome
> grey light; the muted red strip is the only colour. Photorealistic, 35mm
> lens, fine film grain.

What it showed:

- **It begins and ends on the stills.** Frame 1 is K3p and frame 121 is K4p,
  to the eye, so the move joins what the page shows either side of it.
- **The move is a real one.** The camera passes under the lintel about two
  fifths of the way through, crosses the dark, and the room appears ahead at
  about seven tenths and grows. Nothing melts or swaps.
- **The tunnel's ceiling comes out warm and rough** for the second and a half
  after the mouth, where the brief wants cool grey concrete. On a phone it lies
  under the shade the line of text brings and does not show. A final should
  say that the tunnel's walls and ceiling are plain dark grey concrete.
- **The room is not seen from outside.** It comes up out of the dark, because
  K3p's mouth is black and K4p's far end is lit. That is the stills, not the
  model, and in the dark it reads as eyes adjusting.
- **At 540p it is softer than the stills** either side of it, which are 940
  wide. That is what the test size costs, and a final at 1080p does not have
  it.
- **As frames:** 121 at 940 wide come to 5.0 MB, about 43 KB each, and this is
  the darkest of the four moves. Four moves at this density would be too much
  for a phone to fetch, so the tall film wants fewer frames a second.
