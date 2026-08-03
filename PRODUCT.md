# OTP Grabber

## Product

OTP Grabber removes the repetitive handoff between a verification prompt and the code waiting in Gmail or Messages.

## Users

- Primary: MacBook users with an always-on Mac mini or other Apple device running an AI agent.
- Secondary: one-Mac users who run both the local source agent and clients on the same machine.

## Jobs

1. When a site asks for a verification code, open one calm surface and have the freshest code already copied.
2. Retrieve codes from Gmail and SMS/iMessage without exposing the source agent to the public internet.
3. After an email code is copied successfully, archive that email so the inbox stays clean.
4. Keep a short local history available without making it the primary interface.

## Surfaces

- Chrome MV3 popup on the MacBook.
- Native macOS menu-bar application on the MacBook.
- Python source agent on a Mac mini or Apple device.
- GitHub Pages landing page that persuades users to install and gives an AI agent a precise setup path.

## Product principles

- One click, one code, one clipboard.
- Calm confidence. No dashboard density.
- Precision over recall. Showing no code is better than showing the wrong one.
- Private by default. Loopback source service plus Tailscale Serve, never Funnel.
- Secrets remain local. Repository and release artifacts contain no token, account, hostname, or user path.
- Gmail is archived only after confirmed clipboard success.

## Voice

Direct, calm, technically honest. Avoid vague productivity claims, fear language, and security theater.

## Anti-references

- SaaS dashboard grids
- Purple gradients and glow effects
- Glassmorphism
- Excessive pills, borders, and nested cards
- Dense setup forms on the landing page
- Claims that the tool reads passwords or bypasses authentication
