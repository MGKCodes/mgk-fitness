# Runio design system

Runio is **pure greyscale, premium, and unified with Liftio** (see
[ADR-0009](../decisions/0009-greyscale-design-language.md)). Tokens match
Liftio's `constants/Colors.ts` so the two apps read as one product.

## Colour tokens

| Token | Hex | Use |
|---|---|---|
| `bg` | `#1A1A1A` | App background (charcoal, not black) |
| `surface` | `#2D2D2D` | Cards |
| `elevated` | `#404040` | Inputs, elevated surfaces, borders |
| `textPrimary` | `#FFFFFF` | Headings, key numbers |
| `textSecondary` | `#9CA3AF` | Labels, supporting copy |
| `textTertiary` | `#6B7280` | Meta, timestamps, captions |
| `primary` (silver) | `#C0C0C0` | Primary buttons / active control |
| `onPrimary` | `#1A1A1A` | Text/icons on the silver primary |
| `success` | `#16A34A` | **Status only** (on target, complete) |
| `danger` | `#DC2626` | **Status only** (errors, over limit) |

**Colour rule:** greyscale everywhere; `success`/`danger` appear only to signal
status — never as decoration.

**`textSecondary` and `textTertiary` are cool (slate) greys, not neutral ones** —
they carry a slight blue cast, inherited from Liftio deliberately so the two apps
match ([ADR-0009](../decisions/0009-greyscale-design-language.md)). It is most
visible when a text grey is used as a *fill* next to the neutral silver
`primary`. Do not "fix" it to neutral grey in Runio alone; that would break the
parity the decision exists to preserve.

## Typography

- Family: **Inter** (system fallback acceptable; the platform reads as SF-like
  on iOS).
- Weights in use: Thin (hero numerals), Light, Regular, Medium, Semi Bold, Bold,
  Black (wordmark).
- Numerals are the hero — large distance/pace figures carry each screen.

| Role | Weight / size |
|---|---|
| Hero numeral | Thin, 120–150 |
| Display | Semi Bold, 36–44 |
| Title | Semi Bold, 20–24 |
| Body | Regular, 15 |
| Label | Bold, 11–12, letter-spaced (see `SectionLabel`) |
| Wordmark | Black, uppercase, tight tracking |

## Signature treatment: photo + scrim

The premium feel comes from **monochrome photography behind the UI**:

1. Charcoal base fill.
2. A monochrome photo at **~0.25–0.34 opacity**, `FILL`.
3. A vertical **dark gradient scrim** (heavier at top and bottom) so text and
   controls stay crisp while the subject breathes through the middle.

Background images are generated with Replicate `flux-1.1-pro` — fine-art,
high-negative-space, deep-charcoal monochrome running scenes.

## Radius & spacing

Both are scales, in `lib/src/core/theme/app_radius.dart` — pick a step, never a
number. Screens had drifted across seven radii before the scale existed.

| Token | Value | Use |
|---|---|---|
| `AppRadius.chip` | 12 | Chips, tags, inline markers |
| `AppRadius.control` | 16 | Buttons, inputs |
| `AppRadius.card` | 18 | Cards, panels, list rows |
| `AppRadius.sheet` | 20 | Sheets and modals |

`AppSpacing` is a 4-point scale (`xs` 4 → `xxl` 32).

## Components

These live in `lib/src/core/widgets/` and are **the** implementation — build a
screen from them rather than restyling a `Text` to match. That is what keeps the
system real; the drift they replaced came from each screen re-deriving this
section's prose.

- **Primary button** (`PrimaryButton`) — silver `#C0C0C0` fill, `#1A1A1A` text,
  `AppRadius.control`, full-width for CTAs, circular for the in-run pause.
- **Secondary** — text button in `textSecondary`.
- **Section label** (`SectionLabel`) — the letter-spaced uppercase eyebrow.
  `LabelEmphasis.section` heads a section, `.stat` sits above a value, `.hero` is
  the widely-tracked in-run readout.
- **Stat** (`StatBlock`) — value in `textPrimary`, label in **`textSecondary`**.
  `StatSize.standard` / `.large` / `.hero`. Values use tabular figures so a
  ticking pace cannot shift the layout.
- **Card** (`AppCard`) — `surface` fill, `AppRadius.card`.
- **Glass** (`GlassSurface`) — frosted panel. See the rule below before using it.

**Today and focus are different axes.** Today is a **fill** — solid silver with
inverted ink, and it stays the loudest thing on any surface. A focused item (the
day you tapped to get here) is **elevation** — one step up the surface ladder,
`surface` → `elevated`, with its label lifted to `textPrimary`. Never give focus
a silver border: that borrows today's colour at lower contrast and makes two
signals look like one weak version of the same thing.

## Glass: only over texture

`GlassSurface` blurs, brightens and tints what is behind it, with a lit edge and
a top sheen. Verified side by side in the harness (`?screen=glass` over the
photography, `?screen=glass-flat` over the base):

**Over flat charcoal the blur does nothing.** The effect *is* the distortion of
texture, so with nothing behind it a glass pane is a translucent box that costs a
`BackdropFilter` — at blur 8, 16, 24 and 36 the panes are indistinguishable. Only
the tint shows, and a tint is just a container.

So glass belongs only where something sits behind it. In practice that is two
surfaces:

- the **in-run readout**, over the live map. The map is full-bleed and the
  readout floats on it, rather than the two splitting the screen — an opaque
  band would have nothing to refract.
- the **run summary** headline, over the route map, so the distance reads on top
  of the route it describes.

**Welcome and onboarding deliberately do not use it.** They sit over the
signature photography, so glass would work there — but the gradient scrim
already earns the legibility, and a glass pane on top of a scrim is two
treatments doing one job. The scrim is the signature; leave it alone.

The plan arc, the training log, settings and the legal screens sit on the flat
base — they use `AppCard`.

Tuned against the real backgrounds rather than by eye:

| Parameter | Default | Why |
|---|---|---|
| `blurSigma` | 24 | 8 reads as a smudge with the backdrop still legible; 36 flattens it to a wash and loses the sense of depth |
| `tintOpacity` | 0.10 | 0.04 leaves text fighting a busy photo; 0.18 starts to milk over; 0.30 is opaque |
| `luminance` | 1.16 | Greyscale has no saturation to boost, so the lift is what makes the pane read as gathering light |

Legibility over photography is the real constraint — a label can land on a bright
patch. Keep body text at `textPrimary` on glass, and treat a busy backdrop as a
reason to raise the tint rather than to dim the text.
- **Route thumbnail** — a desaturated map: charcoal card, silver route polyline,
  silver start dot / ringed end. (The live in-run map is greyscale `flutter_map`.)

## Signature backdrop

`PhotoBackdrop` is the photo-and-scrim treatment as a component — charcoal fill,
photo at ~0.30, gradient scrim. With no accent colour to carry the brand, this
treatment *is* the brand, so it must be identical everywhere it appears rather
than re-derived per screen.

`ScrimStrength` picks how hard the scrim works: `balanced` for a headline and a
CTA at opposite ends (welcome), `grounded` for content stacking up from the base
(profile), `quiet` where the photo is texture under dense content.

Pass `offset` from a scroll position — a third of the scroll distance is a good
starting point — and the photo drifts behind the content.

## Motion (a design goal, not a polish pass)

Implemented in `lib/src/core/motion/`, and shared so unrelated screens move the
same way:

- **`AppMotion`** — the durations and curves everything else draws from.
- **`Entrance`** — a one-shot fade-and-lift, staggered by `index`, for list rows
  and stacked sections.
- **`CountUp`** — hero numerals counting up on first appearance, tweening
  between values afterwards. With no colour, the numbers *are* the interface, so
  this is what makes a screen feel alive rather than printed.
- **`RunioPageTransitions`** — routes rise and fade instead of Cupertino's
  horizontal slide, which is a different motion language and makes the
  photographic backdrops slide across each other.
- **Parallax** — via `PhotoBackdrop.offset`.

Every one of these honours the platform's reduced-motion setting. Motion is a
genuine barrier for some people, not a preference.

## Figma

Explorations: **"Runio — Hero Explorations"** (`fileKey I0FD6TpIbqMYIkbJHbacp5`).
The chosen in-run direction is the frame **"Runio × Liftio"**.
