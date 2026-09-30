# 0009 — Greyscale design language (unified with Liftio)

**Status:** Accepted. The signature treatment is amended by
[ADR-0042](0042-a-screen-that-leads-with-its-photograph.md) for a screen that
leads with its photograph.

## Context

Runio needed a visual identity, and it is one half of a platform with Liftio
(shared account, cross-readable data, both AI coaches — see
[ADR-0008](0008-shared-supabase-platform.md)). We explored several accent
colours (turquoise, volt, electric blue, coral, violet, amber) across three
in-run screen directions, then a pair of greyscale takes.

Liftio's own palette (`constants/Colors.ts`) is **charcoal greyscale with a
silver primary** and colour reserved for status. The goal for Runio is a
"ridiculously premium" feel that makes the two apps read as one product.
Greyscale delivered both.

## Decision

Runio adopts a **greyscale design language, matching Liftio's tokens exactly.**

- Base `#1A1A1A` charcoal (not pure black); cards `#2D2D2D`; borders `#404040`.
- Text `#FFFFFF` / `#9CA3AF` / `#6B7280`.
- **The greys are cool, not neutral.** `#9CA3AF` and `#6B7280` are slate — they
  carry a slight blue cast rather than being pure achromatic greys, and this is
  inherited from Liftio on purpose. Matching the sibling app is the point of the
  decision, so the cast is deliberate and **must not be "corrected"** to neutral
  greys in Runio alone. Where it is visible — a `textTertiary` fill beside the
  neutral silver `#C0C0C0` primary, as on the deload bar in the plan arc — that
  is the trade-off, not a bug.
- **Primary control = silver `#C0C0C0`** filled, with `#1A1A1A` text.
- Colour (`#DC2626` red / `#16A34A` green) is reserved for **status only**.
- **Signature treatment:** a low-opacity (~0.25–0.34) monochrome photograph
  over the charcoal base, with a dark gradient scrim for legibility.
- Bold uppercase wordmark ("RUNIO", to sit beside "LIFTIO").
- **Motion is first-class:** rich scroll animations are a design goal, not an
  afterthought.

## Consequences

- The two apps share a palette and can later share a Flutter design-system
  package (the units domain is already a candidate).
- With no accent colour to lean on, hierarchy comes from **weight, brightness,
  silver, and space** — a higher bar that keeps the app disciplined.
- Because the text greys are cool and the primary silver is neutral, the palette
  is not strictly achromatic. Changing that is a **platform decision affecting
  both apps**, never a Runio-only edit — the disconfirming condition below is the
  route to reopening it.
- Background imagery is generated (Replicate `flux-1.1-pro`) and treated as a
  design asset. Explorations live in the Figma file "Runio — Hero Explorations".
- Full token/typography/component spec: [design-system.md](../history/design-system.md).
