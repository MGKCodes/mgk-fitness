# mgk_ui

The design system for the MGKCodes fitness suite: **pure greyscale, premium, and
shared**, so every app reads as one product. Extracted from Runio, which took the
palette from Liftio.

```dart
import 'package:mgk_ui/mgk_ui.dart';

MaterialApp(theme: AppTheme.dark, home: ...);
```

`AppTheme.dark` carries the colour scheme, the bundled typeface and the page
transitions. Apps should not build their own `ThemeData`.

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
they carry a slight blue cast, inherited from Liftio deliberately so the apps
match (ADR-0009). It is most visible when a text grey is used as a *fill* next to
the neutral silver `primary`. Do not "fix" it to neutral grey in one app; that
would break the parity the decision exists to preserve.

## Typography

Inter, bundled by this package rather than fetched at runtime so first paint
never waits on a network font. Static weights rather than the variable file:
variable weight-axis mapping is inconsistent across platforms and typography here
is design-critical.

Because the font ships from a package, its family is `packages/mgk_ui/Inter`.
Use `AppTheme.fontFamily` rather than writing `'Inter'`, which would silently
fall back to the platform default.

| Role | Weight / size |
|---|---|
| Hero numeral | Thin, 120–150 |
| Display | Semi Bold, 36–44 |
| Title | Semi Bold, 20–24 |
| Body | Regular, 15 |
| Label | Bold, 11–12, letter-spaced (`SectionLabel`) |
| Wordmark | Black, uppercase, tight tracking |

Numerals are the hero — large figures carry each screen.

## Radius & spacing

Both are scales — pick a step, never a number. Screens had drifted across seven
radii before the scale existed.

| Token | Value | Use |
|---|---|---|
| `AppRadius.chip` | 12 | Chips, tags, inline markers |
| `AppRadius.control` | 16 | Buttons, inputs |
| `AppRadius.card` | 18 | Cards, panels, list rows |
| `AppRadius.sheet` | 20 | Sheets and modals |

`AppSpacing` is a 4-point scale (`xs` 4 → `xxl` 32).

## Components

These are **the** implementation — build a screen from them rather than restyling
a `Text` to match. That is what keeps the system real; the drift they replaced
came from each screen re-deriving this README's prose.

- **`PrimaryButton`** — silver fill, charcoal text, full-width for CTAs, with a
  busy state.
- **Secondary** — a `TextButton`, styled by the theme in `textSecondary`.
- **`SectionLabel`** — the letter-spaced uppercase eyebrow. `LabelEmphasis.section`
  heads a section, `.stat` sits above a value, `.hero` is the widely-tracked
  at-a-glance readout.
- **`StatBlock`** — value in `textPrimary`, label in `textSecondary`.
  `StatSize.standard` / `.large` / `.hero` / `.display`. Values use tabular
  figures so a ticking number cannot shift the layout.
- **`AppCard`** — `surface` fill, `AppRadius.card`. The main structural device.
- **`GlassSurface`** — frosted panel. See the rule below before using it.
- **`PhotoBackdrop`** — the signature photo-and-scrim treatment.

**Today and focus are different axes.** Today is a **fill** — solid silver with
inverted ink, and it stays the loudest thing on any surface. A focused item (the
day you tapped to get here) is **elevation** — one step up the surface ladder,
`surface` → `elevated`, with its label lifted to `textPrimary`. Never give focus
a silver border: that borrows today's colour at lower contrast and makes two
signals look like one weak version of the same thing.

## Glass: only over texture

`GlassSurface` blurs, brightens and tints what is behind it, with a lit edge and
a top sheen.

**Over flat charcoal the blur does nothing.** The effect *is* the distortion of
texture, so with nothing behind it a glass pane is a translucent box that costs a
`BackdropFilter` — at blur 8, 16, 24 and 36 the panes are indistinguishable. Only
the tint shows, and a tint is just a container.

So glass belongs only where something sits behind it — over the signature
photography or over a live map. Content on the flat base uses `AppCard`.

Note that a glass pane on top of a scrim is two treatments doing one job: where
`PhotoBackdrop`'s scrim already earns the legibility, leave it alone.

Tuned against real backgrounds rather than by eye:

| Parameter | Default | Why |
|---|---|---|
| `blurSigma` | 24 | 8 reads as a smudge with the backdrop still legible; 36 flattens it to a wash and loses the sense of depth |
| `tintOpacity` | 0.10 | 0.04 leaves text fighting a busy photo; 0.18 starts to milk over; 0.30 is opaque |
| `luminance` | 1.16 | Greyscale has no saturation to boost, so the lift is what makes the pane read as gathering light |

Legibility over photography is the real constraint — a label can land on a bright
patch. Keep body text at `textPrimary` on glass, and treat a busy backdrop as a
reason to raise the tint rather than to dim the text.

## Signature backdrop

`PhotoBackdrop` is charcoal fill, a monochrome photo at ~0.30, and a gradient
scrim. With no accent colour to carry the brand, this treatment *is* the brand,
so it must be identical everywhere rather than re-derived per screen.

**The treatment is shared; the photography is not.** Each app declares its own
images and passes an asset path, so the running app shows running scenes and the
lifting app shows lifting ones with no change to the component.

`ScrimStrength` picks how hard the scrim works: `balanced` for a headline and a
CTA at opposite ends, `grounded` for content stacking up from the base, `quiet`
where the photo is texture under dense content.

Pass `offset` from a scroll position — a third of the scroll distance is a good
starting point — and the photo drifts behind the content.

## Motion (a design goal, not a polish pass)

Shared so unrelated screens, in unrelated apps, move the same way:

- **`AppMotion`** — the durations and curves everything else draws from.
- **`Entrance`** — a one-shot fade-and-lift, staggered by `index`, for list rows
  and stacked sections.
- **`CountUp`** — hero numerals counting up on first appearance, tweening between
  values afterwards. With no colour, the numbers *are* the interface, so this is
  what makes a screen feel alive rather than printed.
- **`MgkPageTransitions`** — routes rise and fade instead of Cupertino's
  horizontal slide, which is a different motion language and makes the
  photographic backdrops slide across each other.
- **Parallax** — via `PhotoBackdrop.offset`.

Every one of these honours the platform's reduced-motion setting. Motion is a
genuine barrier for some people, not a preference.
