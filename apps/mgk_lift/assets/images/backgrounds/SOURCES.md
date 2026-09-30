# Where the Track and Sign-in heroes come from

Generated on 2026-09-30 with FLUX 1.1 [pro] Ultra (`black-forest-labs/flux-1.1-pro-ultra`,
raw mode, 2:3) on Replicate, as ADR-0009 describes for the suite's backgrounds,
then converted to greyscale and resized to 1290 px wide.

| File | Seed | Prompt | After |
|---|---|---|---|
| `hero_track.webp` | 4102 | *Black and white documentary photograph inside a quiet gym at dusk: rows of dumbbells and a lifting platform with a loaded barbell on the floor, lit by a single warm window light from the side, long shadows. The upper third of the frame is dark empty ceiling and wall, calm negative space. Shallow depth of field, fine film grain. No people, no text, no logos.* | shadows lifted (gamma 0.8) |
| `hero_sign_in.webp` | 4301 | *Black and white cinematic photograph: the silhouette of a lifter standing on a wooden lifting platform, facing a tall bright window at dawn, strongly backlit, soft haze in the air, the rest of the gym in darkness. Upper third of the frame is dark and empty. Minimal, calm, premium, fine film grain. Silhouette only, no face or skin detail, no text, no logos.* | none |

**Chosen over the alternatives by looking at full resolution, not thumbnails.**
Two of the six candidates failed there: a rack with garbled lettering on its
uprights, and an athlete whose forearms had the glossy, streaked skin image
models leave. Silhouettes and light hold up; skin and lettering do not, so ask
for those when one of these is regenerated.

Until these, two Unsplash photographs stood in (Brett Jordan's rack, Edgar
Chaparro's pull-up); both are gone from the app.

This file covers those two images only, not the other heroes in this folder.
