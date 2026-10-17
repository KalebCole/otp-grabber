# Changelog

All notable changes appear here. This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Removed the retired Python source agent, Chrome extension, remote setup scripts,
  and Chrome release artifact. Releases now contain the native macOS app and
  source archive.
- Native app tests and build are the only release verification path.

### Known limits

- Gmail code copying and the remaining live acceptance checks on the target Mac
  have not been confirmed.

## [0.1.0] - 2026-08-02

Historical release; its Python agent, Chrome extension, and remote setup were
removed from the current repository after the native Mac app became the sole
supported path.

### Added

- Loopback-only Python source agent for Gmail and Messages verification codes.
- Constant-time bearer authentication, bounded requests, rate limiting, and private configuration.
- Calm Card Chrome MV3 extension with automatic clipboard copy and post-copy Gmail archive.
- Native macOS menu-bar client with the same copy-before-archive guarantee.
- Tailnet-only Tailscale Serve helper. Public Funnel exposure is explicitly rejected.
- Responsive GitHub Pages landing page, setup prompt, CI, release packaging, and security documentation.

[Unreleased]: https://github.com/KalebCole/otp-grabber/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/KalebCole/otp-grabber/releases/tag/v0.1.0
