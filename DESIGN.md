# OTP Grabber Design System

## Direction

Calm Card. A focused utility that feels native beside macOS, not a miniature admin dashboard.

## Typography

- UI: `Avenir Next`, with `-apple-system` fallback.
- Codes: `SF Mono`, `ui-monospace` fallback.
- Landing display: `Instrument Serif` may be used for one high-impact phrase only; interface labels remain Avenir Next.

## Color

- Canvas: warm white `#F6F4EF`
- Surface: `#FFFDF8`
- Ink: blue-black `#17212B`
- Muted ink: `#68717A`
- Accent: calm sage `#547565`
- Success tint: `#E5F0E8`
- Warning tint: `#F4EBD7`
- Error: `#A7443E`
- Hairline: `#DFDCD3`

No pure black. No purple. No decorative gradients.

## Shape and spacing

- Popup width: 356px.
- Primary card radius: 18px. Controls: 10px. Do not round every container.
- Base spacing unit: 4px. Primary rhythm: 8, 12, 16, 24, 32.
- One primary surface. History is a disclosure, not a competing panel.

## Motion

- 140 to 220ms ease-out transitions.
- No bounce, elastic, or continuous decorative motion.
- Loading uses a restrained rotating stroke and preserves layout.
- Respect `prefers-reduced-motion`.

## Calm Card states

1. Loading: quiet progress label, stable frame.
2. Success: source and age above a large code, copied confirmation below.
3. Empty: direct message that no recent code was found, with refresh action.
4. Partial: show the available source result and one unobtrusive source warning.
5. Offline: setup affordance, never a raw stack trace.
6. History: hidden by default, newest first, each row copyable.

## Accessibility

- WCAG AA contrast.
- Keyboard reachable controls and visible focus.
- Minimum 36px pointer targets in compact surfaces, 44px on landing.
- Semantic headings and status announcements.
- Codes remain selectable and are announced as grouped characters.

## Landing mode

Persuade, then hand off to setup. Hero tells the repeated-action pain in one line, demonstrates the handoff visually, and presents only two CTAs: install the latest release or copy the AI-agent setup prompt.
