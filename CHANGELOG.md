# Changelog

All notable changes appear here. This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### In progress

- Added a local Swift source reader, OAuth and Keychain groundwork, a menu bar panel,
  and private one-day finding history. The native migration awaits macOS build and
  live acceptance before replacing the 0.1.0 release path.

## [0.1.0] - 2026-08-02

### Added

- Loopback-only Python source agent for Gmail and Messages verification codes.
- Constant-time bearer authentication, bounded requests, rate limiting, and private configuration.
- Calm Card Chrome MV3 extension with automatic clipboard copy and post-copy Gmail archive.
- Native macOS menu-bar client with the same copy-before-archive guarantee.
- Tailnet-only Tailscale Serve helper. Public Funnel exposure is explicitly rejected.
- Responsive GitHub Pages landing page, setup prompt, CI, release packaging, and security documentation.

[Unreleased]: https://github.com/KalebCole/otp-grabber/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/KalebCole/otp-grabber/releases/tag/v0.1.0
