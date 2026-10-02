# The clips

One short video per move, made by a video model from two stills: the move's
first frame and its last. `node tool/film.mjs frames <move> <clip>` cuts one
into the frames the page plays.

The videos are not committed. Each is several megabytes and the page uses only
the frames cut from them, so they stay in this folder on the disk they were
made on, as the stills' rounds do. This file records each one, so that a clip
can be made again the same way, and [`edits.json`](edits.json) holds what is
done to a clip as it is cut.

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
  those files and nothing else, through a temporary tunnel
  (`cloudflared tunnel --url`), which is closed as soon as the clips are made.
- **Create the prediction and then ask after it. Never wait on the request.**
  See below: this cost $1.41.
- **The output is deleted from Replicate after an hour**, so it is downloaded
  at once.
- **A test is 540p and a final is 1080p.** The same seed at another size is
  another roll, so a good test proves the model and the prompt. It does not
  preview the final. The same seed at the same size gives the same clip.

### The retry that cost $1.41

On 2 October two tests were sent with `Prefer: wait`, which holds the request
open for up to a minute. Both clips took longer than that. The connection to
Replicate gave up at sixty seconds and sent each request again, twice, and
every one of the six requests made a clip and was billed: $2.12 where $0.71
was meant. Four of the six were not wanted, and three of those were the same
clip again, frame for frame.

A prediction made without `Prefer: wait` comes back at once as `starting`, so
nothing times out and nothing is sent twice. That is the only way one is made
now, and the account's list of predictions is read after each to see that
there is one and not three.

## Cutting a clip

- **The tall film takes 12 frames a second** and the wide one 24. A phone
  fetches the tall film, and at 12 the four moves come to 9.6 MB; at 24 they
  would be twice that. The first and last frames are kept either way.
- **A clip can be edited as it is cut.** `edits.json` gives, by the clip's
  file name, an ffmpeg filter graph that takes `[0:v]` and ends in `[v]`. The
  clip itself is left as it was made. Two are edited:
  - `s3p-1080p.mp4` is **re-paced**. The model spent three and a half of its
    five seconds creeping towards the mouth and the last second and a half on
    everything else. The first part is played at twice the speed and the
    second at half, so the lintel passes overhead at about two fifths of the
    way through and the room appears at about five sixths.
  - `s4p-1080p.mp4` has a **jump dissolved**. See its entry.

## What has been made

All on 2 October 2026, all `vidu/q3-pro`, audio off, seed 29, upright.

| Clip | Move | Size | Seconds | Cost | Prediction |
|---|---|---|---|---|---|
| `s3p-test-540p.mp4` | `s3`, K3p to K4p | 540p | 5 | $0.35 | `s9jzhzccx9rmr0d0znk957m9s8` |
| `s1p-test-540p-a.mp4` | `s1`, K1p to K2p | 540p | 5 | $0.35 | `7zw62vvqhdrmw0d0znsvpawchr` |
| `s1p-test-540p-b.mp4` | `s1` | 540p | 5 | $0.35 | `jbrnwak391rmw0d0zntbw51ktm` |
| (the same as `b`, not kept) | `s1` | 540p | 5 | $0.35 | `hvjvf9jhk5rmt0d0zntstw98s4` |
| `s2p-test-540p.mp4` | `s2`, K2p to K3p | 540p | 5 | $0.35 | `dvft0q1w4srmt0d0znvadb7dnw` |
| (the same again, twice, not kept) | `s2` | 540p | 5 | $0.71 | `nt4htas8gxrmt0d0znvt4bpdmm`, `xcc5b98nkdrmr0d0znwam81mnw` |
| **`s1p-1080p.mp4`** | `s1` | 1080p | 5 | $0.81 | `ebcgtfghsxrmt0d0znxrqg4fkr` |
| **`s2p-1080p.mp4`** | `s2` | 1080p | 5 | $0.81 | `87qc9jjy6xrmw0d0znytpydnr4` |
| **`s3p-1080p.mp4`** | `s3` | 1080p | 5 | $0.81 | `cqfd04m6ksrmr0d0znys7qbyf8` |
| **`s4p-1080p.mp4`** | `s4`, K4p to K5p | 1080p | 3 | $0.49 | `0g6480nfkxrmy0d0znyttfc1b8` |

$5.38 in all. The four in bold are on the page.

### `s1`, the descent: good

> One continuous drone shot, no cuts. The camera starts high above an empty
> athletics track, looking straight down at the red lanes and their painted
> numbers. It descends smoothly and steadily while tilting up, until it is one
> metre above the track, looking straight ahead along the lanes to where they
> meet the horizon, with the grandstand on the right. Smooth, slow and steady,
> no shake; the lanes stay straight and parallel and keep running straight
> ahead the whole way. The scene is empty and still: no people, nothing moves
> except the camera. Overcast, cool, nearly monochrome grey light; the muted
> red track is the only colour. Photorealistic, fine film grain.

One crane down with the lane numbers passing under the camera and the horizon
coming up. The lanes hold. Both 540p tests bent the track part of the way
down; the final, with "the lanes stay straight and parallel" added, does not.

### `s2`, the turn to the tunnel: good, with a wobble

> One continuous shot, no cuts. The camera glides forward along the empty
> running track, one metre above it, then curves smoothly to the right,
> leaving the track along the strip of red surface that crosses the concrete
> apron, and comes to rest facing the dark tunnel entrance in the base of the
> grandstand square on, with rows of empty seats rising above it. Smooth and
> steady, no shake. The scene is empty and still: no people, nothing moves
> except the camera. Overcast, cool, nearly monochrome grey light; the muted
> red surface is the only colour. Photorealistic, 35mm lens, fine film grain.

The model turns the camera to the right more than it travels, and the stand
swings round to face it. It reads as one move. Between about three fifths and
three quarters of the way the red strip and the track change shape under the
camera as the model works out which is which.

### `s3`, the tunnel: good once re-paced

> Slow, steady forward dolly shot. The camera glides straight ahead at walking
> pace along the red running-track strip, through the concrete tunnel mouth
> and on down the dark tunnel, towards the lit weight room at its far end. The
> tunnel's walls and ceiling are plain, cool, dark grey concrete, almost
> black. The camera stays level, one metre above the ground, pointing straight
> ahead: no pan, no tilt, no zoom, no shake. The scene is empty and still: no
> people, nothing moves except the camera. Overcast, cool, nearly monochrome
> grey light; the muted red strip is the only colour. Photorealistic, 35mm
> lens, fine film grain.

The sentence about the walls and ceiling is new since the test, whose ceiling
came out warm and rough; this one is cool and dark. The room is not seen from
outside: it comes up out of the dark, because K3p's mouth is black and K4p's
far end is lit. That is the stills, and in the dark it reads as eyes adjusting.

### `s4`, into the weight room: the weak one

> Slow, steady forward dolly shot. The camera glides straight ahead along the
> red strip on the floor, out of the dark concrete tunnel and into the weight
> room, towards the steel power rack with a loaded barbell that stands on a
> lifting platform in the middle of the room. The camera stays level, one
> metre above the floor, pointing straight ahead: no pan, no tilt, no zoom, no
> shake. The room is empty and still: no people, nothing moves except the
> camera. Cool, nearly monochrome grey light; the muted red strip is the only
> colour. Photorealistic, 35mm lens, fine film grain.

**The two stills show two different rooms.** Through the tunnel, K4p's room is
a bright hall: pale floor, slanting columns, daylight from above. K5p's is the
room the film ends in: black rubber floor, strip lights, a window on the
right. The model walks into the first and, at frame 51 of 73, cuts to the
second between one frame and the next.

`edits.json` dissolves across that cut over ten frames, so on the page it is a
change of light and not a jump. It is still two rooms. The cure is a K4p whose
far end is K5p's room, made from K5p, and then `s3` and `s4` made again from
it: $1.30 at these prices. The wide K4 and K5 have the same difference.
