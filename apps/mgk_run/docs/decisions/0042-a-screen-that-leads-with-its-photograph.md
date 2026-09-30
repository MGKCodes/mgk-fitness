# 0042 — A screen that leads with its photograph may carry it at strength

**Status:** Accepted, 2026-09-30. Amends
[ADR-0009](0009-greyscale-design-language.md)'s signature treatment; the rest of
0009 stands.

## Context

ADR-0009 made the photograph the brand and set how it is shown everywhere: a
monochrome image at about 0.25–0.34 opacity over the charcoal base, under a
scrim. With no accent colour, that treatment is what makes both apps read as
one product.

Lift's design review of 30 September 2026 found its front page did not work
(finding 2), and the references it was measured against let a photograph carry
the top of the screen, with the headline set on it. At 0.3, under a scrim, a
photograph behind a headline is a rumour rather than a subject: the page read
as a dark screen with a faint texture, and the one visual decision this
product makes was being thrown away on the screen people open most. Decision
R1 of the redesign kept the greyscale language and asked for exactly this
change, as a platform decision rather than a Lift edit, because both apps use
the treatment.

## Decision

- **A screen that leads with its photograph** may show it at strength —
  `PhotoBackdrop.hero` in `mgk_ui`: 0.82 opacity, full width, top-aligned, under
  a scrim (`ScrimStrength.hero`) that is light where the headline sits, open
  through the middle, and solid charcoal by two-thirds of the way down, so
  everything below it is on the base, not on the photograph.
- **Which screens lead with one is a short list, decided per screen:** in Lift,
  Track and Sign in. Everywhere else the faint texture stands, as 0009 wrote it.
- **The images for it are composed for it**: a subject that leaves the top third
  for a headline and a dark floor for what sits below. Lift's are generated
  (`apps/mgk_lift/assets/images/backgrounds/SOURCES.md`), as 0009 has all
  background imagery made.
- **A workout sits on no photograph at all**: a dark gradient with one soft light
  (`GlowBackdrop`), so its glass has something to blur without anything to read
  past (Lift's R13).

## Consequences

- The brand gets louder exactly where it is seen first, and nowhere else. A
  screen of dense content still sits on the texture, which is what keeps text
  crisp and the photograph from competing with it.
- Two treatments means a choice per screen, which is a place to drift. The
  list above is the rule; a screen joins it by being one somebody opens to see
  the product, not by wanting to look nicer.
- Run can adopt it for its own front page without a new decision, provided the
  image is composed for it.

**Disconfirming condition:** if a screen at strength fails legibility at the
largest text size, or a screen joins the list because it "looked flat" rather
than because it leads with its photograph, the treatment has become decoration
and the list should shrink back to what 0009 allowed.
