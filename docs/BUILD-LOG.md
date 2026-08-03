# Build Log

## Task 1: Repository and test harness

Date: 2026-08-02

The initial harness directories were intentionally empty. Commands were run
from the repository root. Worktree-specific path text is represented as
`[worktree]` so this public log contains no personal absolute paths.

### Red

#### Python

- Command: `python3 -m unittest discover -s agent/tests -v`
- Expected: the empty `unittest` harness reports that it discovered no tests.
- Observed: exit 5; `Ran 0 tests in 0.000s` and `NO TESTS RAN`.

#### JavaScript

- Command: `node --test extension/tests`
- Expected: the empty Node harness has no loadable test module.
- Observed: exit 1; `MODULE_NOT_FOUND` for `[worktree]/extension/tests`,
  followed by `tests 1`, `pass 0`, and `fail 1`.

#### Swift

- Command: `swift test --package-path menubar`
- Expected: Swift Package Manager cannot run before package scaffolding exists.
- Observed: exit 1; `error: Could not find Package.swift in this directory or
  any of its parent directories.`

#### Swift scaffolding compatibility

- Command: `make test-swift`
- Expected: the scaffolded XCTest smoke test passes.
- Observed: exit 2 from `make` after Swift reported
  `error: no such module 'XCTest'`. The active Command Line Tools installation
  includes Swift Package Manager but not the XCTest module or `xctest` runner.
  The XCTest smoke test was therefore guarded with `canImport(XCTest)` so the
  same package runs as an empty harness under Command Line Tools and runs the
  smoke test where XCTest is available.

### Green

- Command: `make test-python`
- Result: exit 0; one `unittest` smoke test ran and passed (`OK`).
- Command: `make test-js`
- Result: exit 0; one `node:test` smoke test ran and passed
  (`tests 1`, `pass 1`, `fail 0`).
- Command: `make test-swift`
- Result: exit 0; Swift Package Manager built the XCTest-guarded test target
  successfully (`Build complete! (1.39s)`). No test is discovered when XCTest
  is absent from Command Line Tools.
- Command: `make test`
- Result: exit 0; Python reported one passing test, Node reported one passing
  test and zero failures, and Swift Package Manager completed its build
  successfully (`Build complete! (0.06s)`).

## Task 2: Shared code extraction and source adapters

Date: 2026-08-02

Commands were run from the worktree root.

### Extraction red

- Command: `python3 -m unittest agent.tests.test_extractor -v`
- Expected: exit 1 because the focused extraction tests import behavior that
  has not been implemented yet.
- Observed: exit 1; test discovery reached `test_extractor.py` and failed with
  `ModuleNotFoundError: No module named 'agent.otp_grabber.extractor'`. This
  was the expected missing-implementation failure, not a syntax failure.

### Extraction green

- Command: `python3 -m unittest agent.tests.test_extractor -v`
- Expected: all focused extraction and typedstream tests pass.
- Observed: exit 0; 12 tests ran and passed (`OK`).

### Source adapters red

- Command: `python3 -m unittest agent.tests.test_sources -v`
- Expected: exit 1 because the Gmail and Messages adapters do not exist yet.
- Observed: exit 1; test discovery reached `test_sources.py` and failed with
  `ModuleNotFoundError: No module named 'agent.otp_grabber.sources.gmail'`.
  This was the expected missing-implementation failure, not a syntax failure.

### Source adapters green

- Command: `python3 -m unittest agent.tests.test_sources -v`
- Expected: both fixture-backed adapter tests pass without accessing live
  Gmail or Messages data.
- Observed: exit 0; 2 tests ran and passed (`OK`).

### Full Python suite green

- Command: `make test-python`
- Expected: the complete Python suite passes before refactoring.
- Observed: exit 0; 15 tests ran and passed (`OK`).
- Command: `make test-python`
- Expected: the complete Python suite remains green after the package and
  timestamp-arithmetic refactor.
- Observed: exit 0; 15 tests ran and passed (`OK`).
- Command: `make test-python`
- Expected: final pre-commit verification remains green.
- Observed: exit 0; 15 tests ran and passed (`OK`).

## Task 3: Freshest-code service and Gmail archive protocol

Date: 2026-08-02

Commands were run from the worktree root.

### Freshest-code service red

- Command: `python3 -m unittest agent.tests.test_service -v`
- Expected: exit 1 because the focused tests import the not-yet-implemented
  freshest-code service.
- Observed: exit 1; test loading failed with `ModuleNotFoundError: No module
  named 'agent.otp_grabber.service'`. This was the expected
  missing-implementation failure.

### Freshest-code service green

- Command: `python3 -m unittest agent.tests.test_service -v`
- Expected: concurrent polling, ordering, source-error, history, deduplication,
  bounding, and expiration tests pass.
- Observed: exit 0; 6 tests ran and passed (`OK`).

### Gmail archive protocol red

- Command: `python3 -m unittest
  agent.tests.test_service.ArchiveAcknowledgementTests -v`
- Expected: exit 1 because archive acknowledgment and Gmail modification have
  not been implemented.
- Observed: exit 1; 5 tests ran and errored with the expected missing-method
  failures: `FreshestCodeService` had no `acknowledge_archive`, and
  `GmailSource` had no `archive_message`.

### Gmail archive protocol green

- Command: `python3 -m unittest
  agent.tests.test_service.ArchiveAcknowledgementTests -v`
- Expected: eligibility, rejection, one-time modification, idempotency, and
  retry tests pass without live Gmail access.
- Observed: exit 0; 5 tests ran and passed (`OK`).
- Command: `python3 -m unittest agent.tests.test_sources -v`
- Expected: existing source adapter behavior remains green.
- Observed: exit 0; 2 tests ran and passed (`OK`).
- Command: `python3 -m unittest agent.tests.test_service -v`
- Expected: the complete focused service and archive suite passes.
- Observed: exit 0; 11 tests ran and passed (`OK`).

### Full Python suite green

- Command: `make test-python`
- Expected: all Python tests pass after the service and archive changes.
- Observed: exit 0; 26 tests ran and passed (`OK`).

### Task 3 code-quality remediation red

- Command: `python3 -m unittest
  agent.tests.test_service.ArchiveAcknowledgementTests.test_archive_eligibility_is_pruned_with_bounded_history
  -v`
- Expected: exit 1 because archive eligibility and idempotency bookkeeping
  outlives the bounded recent history.
- Observed: exit 1; 1 test ran and failed at
  `assertRaisesRegex(ValueError, "not eligible")` with
  `AssertionError: ValueError not raised` (`FAILED (failures=1)`).
- Command: `python3 -m unittest
  agent.tests.test_service.ArchiveAcknowledgementTests.test_history_access_proceeds_while_archive_io_is_blocked
  -v`
- Expected: exit 1 because `get_history` cannot acquire the service lock while
  injected archive I/O is blocked.
- Observed: exit 1; 1 test ran and failed at
  `history_returned.wait(timeout=1)` with `AssertionError: False is not true :
  get_history blocked behind archive I/O` (`FAILED (failures=1)`).

### Task 3 code-quality remediation green

- Command: `python3 -m unittest
  agent.tests.test_service.ArchiveAcknowledgementTests.test_archive_eligibility_is_pruned_with_bounded_history
  agent.tests.test_service.ArchiveAcknowledgementTests.test_history_access_proceeds_while_archive_io_is_blocked
  -v`
- Expected: stale archive state is pruned and history remains accessible during
  blocked archive I/O.
- Observed: exit 0; both focused tests ran and passed (`Ran 2 tests`,
  `OK`).
- Command: `make test-python`
- Expected: the complete Python suite remains green.
- Observed: exit 0; 28 tests ran and passed (`OK`).

### Task 3 spec-review concurrency coverage green

- The two archive-concurrency tests use condition/event handshakes rather than
  sleeps. Existing behavior passed on the first run, so no red result was
  recorded.
- Command: `python3 -m unittest
  agent.tests.test_service.ArchiveAcknowledgementTests.test_concurrent_acknowledgements_share_one_successful_archive_attempt
  agent.tests.test_service.ArchiveAcknowledgementTests.test_concurrent_archive_failure_reaches_both_callers_and_can_retry
  -v`
- Expected: concurrent callers share one external attempt; success returns one
  new and one idempotent result, while one failure reaches both callers and a
  later retry performs a second external attempt successfully.
- Observed: exit 0; both focused tests ran and passed (`Ran 2 tests`, `OK`).
- Command: `python3 -m unittest agent.tests.test_service -v`
- Expected: the complete focused service suite remains green.
- Observed: exit 0; 15 tests ran and passed (`OK`).
- Command: `make test-python`
- Expected: the complete Python suite remains green.
- Observed: exit 0; 30 tests ran and passed (`OK`).

## Task 4: Authenticated localhost API and installer

Date: 2026-08-02

Commands were run from the worktree root using an available Python 3.14
interpreter because the system `python3` resolves to Python 3.9 while this
project requires Python 3.11 or newer.

### API and config red

- Command: `/opt/homebrew/bin/python3 -m unittest agent.tests.test_api -v`
- Expected: exit 1 because `security`, `server`, and `config` modules had not
  been created.
- Observed: exit 1; import failed with `ModuleNotFoundError: No module named
  'agent.otp_grabber.security'`.

### API and config green

- Command: `/opt/homebrew/bin/python3 -m unittest agent.tests.test_api -v`
- Expected: loopback binding, bearer authentication, constant-time token
  matching, endpoint contract, malformed JSON, 64 KiB cap, route/method
  allowlist, rate cap, restricted CORS, safe errors, and mode-600 config pass.
- Observed: exit 0; 12 tests ran and passed (`OK`).

### Installer red

- Command: `/opt/homebrew/bin/python3 -m unittest agent.tests.test_scripts -v`
- Expected: exit 1 before the installer, uninstaller, Tailscale helper, and
  plist template existed.
- Observed: exit 1; all four tests reported missing script paths (exit 127).

### Installer green

- Command: `/opt/homebrew/bin/python3 -m unittest agent.tests.test_scripts -v`
- Expected: dry-run install/uninstall work without mutation; the private
  Tailscale command is emitted; and public-exposure input is rejected.
- Observed: exit 0; 4 tests ran and passed (`OK`).
- Command: `bash -n scripts/install-agent.sh scripts/uninstall-agent.sh
  scripts/serve-tailnet.sh && plutil -lint
  scripts/com.otpgrabber.agent.plist.template && shellcheck
  scripts/install-agent.sh scripts/uninstall-agent.sh scripts/serve-tailnet.sh`
- Observed: exit 0; plist template reported `OK` and ShellCheck reported no
  findings.
- Command: `bash scripts/install-agent.sh --dry-run && bash
  scripts/uninstall-agent.sh --dry-run && bash scripts/serve-tailnet.sh
  --dry-run --port 8787 && ! bash scripts/serve-tailnet.sh --funnel --dry-run`
- Observed: exit 0; dry-run output described only a loopback target, and the
  public-exposure flag was rejected without running Tailscale or launchctl.

### Full Python suite green

- Command: `/opt/homebrew/bin/python3 -m unittest discover -s agent/tests -v`
- Observed: exit 0; 46 tests ran and passed (`OK`).
- Command: `git diff --check`
- Observed: exit 0; no whitespace errors.

## Task 7: Landing page

Date: 2026-08-02

### Static implementation green

- Added a dependency-free GitHub Pages surface in `docs/` with a product-specific
  transfer-path demonstration, responsive layouts, semantic landmarks, two setup
  actions, a clipboard fallback, a social card, and a branded 404 page.
- Command: `node --check docs/app.js`
- Observed: exit 0.
- Command: `node .github/skills/impeccable/scripts/detect.mjs docs/ --json`
- Initial observation: one advisory finding for a decorative grid-line background.
  The generated-UI signature was removed rather than waived.
- Final observation: exit 0 with `[]` and zero findings.

### Visual verification green

- Desktop capture: headless Chrome at 1440 × 1000.
- Mobile capture: headless Chrome at 390 × 844.
- Both captures rendered the expected typography, actions, responsive wrapping,
  and Calm Card demonstration without horizontal overflow or clipped controls.
- Browser URL detection could not run because the optional Puppeteer dependency
  is not installed. Static detector and real Chrome screenshots were used instead.

## Task 5: Calm Card Chrome extension

Date: 2026-08-02

Commands were run from the worktree root. The extension contains no personal
server address, token, or private key. Its manifest contains only a public key
so Chrome derives a stable unpacked-extension ID.

### Pure model/API red

- Command: `npm run test:extension`
- Expected: exit 1 before the new pure modules exist.
- Observed: exit 1; Node reported `ERR_MODULE_NOT_FOUND` for
  `extension/src/api.js` and `extension/src/model.js`. The existing harness
  test still passed, confirming the failure was missing implementation.

### Pure model/API green

- Command: `npm run test:extension`
- Expected: normalization, freshness, state derivation, URL validation,
  authenticated endpoint construction, and copy-before-archive behavior pass.
- Observed: exit 0; 13 tests passed, zero failed.

### Manifest/CSP red

- Command: `node --test extension/tests/manifest.test.js`
- Expected: exit 1 before the MV3 manifest and extension documents exist.
- Observed: exit 1; both tests failed with `ENOENT` for
  `extension/manifest.json`.

### Manifest/CSP green

- Command: `node --test extension/tests/manifest.test.js`
- Expected: the manifest is MV3 with a public key and minimum permissions, and
  both documents use external modules under a restrictive CSP.
- Observed: exit 0; 2 tests passed, zero failed.
- Command: `npm run test:extension`
- Observed: exit 0; 15 tests passed, zero failed.
- Command: `node --check extension/src/api.js && node --check
  extension/src/model.js && node --check extension/src/popup.js && node --check
  extension/src/options.js`, plus a Python manifest/CSP/PNG assertion script
  and `git diff --check`.
- Observed: exit 0; syntax checks completed and the assertion script printed
  `manifest/CSP/icon checks: OK`.

### Full suite

- Command: `PYTHON=/opt/homebrew/bin/python3 make test`
- Observed: exit 0; 30 Python tests passed, 15 Node tests passed, and the
  Swift package built successfully. The shell default `python3` resolves to
  Command Line Tools Python 3.9 on this host and cannot import the repository's
  Python-3.11+ `dataclass(slots=True)` code; the explicit Homebrew Python 3.14
  override was required for the complete suite.


## Task 6: Native macOS menu-bar app

Date: 2026-08-02

Commands were run from the worktree root. The artifact is generated under the
ignored `dist/` directory; no client configuration, source-agent data, or user
LaunchAgent was read or modified during verification.

### XCTest-first red

- Added focused XCTest cases before the production model/API/controller files:
  configuration parsing, freshest response selection, partial source errors,
  agent `latest` response shape, archive request construction, copy-before-
  archive ordering, and offline behavior.
- Command: `swift test --package-path menubar`
- Observed: exit 1 before implementation. The initial package had no core
  source target; after package scaffolding, the active Command Line Tools
  installation reported `no such module 'XCTest'`. This is the same documented
  CLT limitation from Task 1, so the XCTest source is guarded with
  `canImport(XCTest)` for CLT-only builds. The tests will run unchanged when
  XCTest is available (for example, in a full Xcode/CI environment).

### Green and packaging

- Command: `swift test --package-path menubar`
- Result: exit 0; Swift Package Manager built the core, native app, and test
  target successfully under Command Line Tools. XCTest discovery is unavailable
  on this host because the CLT toolchain lacks the XCTest module.
- Command: `scripts/build-menubar.sh`
- Result: exit 0; created an arm64 release `OTP Grabber.app`, generated an
  `Info.plist` with `LSUIElement=true`, ad-hoc signed and strictly verified the
  bundle, linted the plist, and created the arm64 zip release artifact.
- Command: `bash -n scripts/build-menubar.sh scripts/install-menubar.sh` and
  `shellcheck scripts/build-menubar.sh scripts/install-menubar.sh`
- Result: exit 0.
- Command: `PYTHON=/opt/homebrew/bin/python3 make test`
- Result: exit 0; 30 Python tests passed, one Node test passed, and the Swift
  package build completed. The explicit Python selection avoids the system
  Command Line Tools Python 3.9, which cannot import the repository's
  `@dataclass(slots=True)` models.

### Artifact and process smoke

- Command: `plutil -extract LSUIElement raw`, `codesign --verify --deep
  --strict`, and `unzip -l` against the built artifact.
- Result: `true`; code signature valid and satisfying its designated
  requirement; the zip contains the signed app executable and Info.plist.
- Command: launch the packaged executable with a freshly created temporary
  `HOME`, check that its PID remains alive, then terminate it.
- Result: the process remained running through the two-second check and was
  explicitly stopped. It could only show the setup state because the temporary
  home contained no `client.json`; no live configuration or source data was
  touched.

## Task 8: Documentation, CI, release, and final local verification

Date: 2026-08-02

### Integration defects fixed

- Chrome cross-origin fetch initially had no host permission. Added narrow optional
  `.ts.net` and loopback permissions, requested only the selected origin at setup,
  and added manifest/UI regression coverage.
- Removed the rejected manual refresh control from the Calm Card. Copy status now
  changes to success only after the clipboard write succeeds.
- Tailscale Serve helper initially ran in the foreground. Verified the installed
  CLI contract and added `--bg --yes` with focused tests.
- Menu-bar release script initially printed Swift's bin path without compiling a
  release binary. The first package run failed; the script now performs the release
  build before copying and signing the app.
- Menu-bar configuration now rejects public HTTPS hosts, credentials, and paths.
  Gmail archive failure preserves the copied code and presents retry guidance.

### Full verification green

- Command: `PYTHON=python3.11 make test`
- Observed: 46 Python tests, 16 Chrome extension tests, 5 landing-page tests,
  and 8 framework-free Swift client checks passed. The Swift package also built
  successfully under Command Line Tools on both the source Mac and MacBook.
- Command: `make check`
- Observed: repository hygiene passed and Impeccable detector returned `[]`.
- Command: `VERSION=0.1.0 make package`
- Observed: extension zip, signed arm64 menu-bar zip, and source tarball created.
  `codesign --verify --deep --strict` and `plutil -lint` passed.
- Workflow YAML parsed successfully for verification, Pages, and release jobs.
  Tag-derived packaging was exercised with `v0.1.1`, producing correctly named
  artifacts under `dist/release/`; invalid versions were rejected.
- `git diff --check` passed.

### Live private-network verification

- Installed the source LaunchAgent on the Mac mini. It runs on
  `127.0.0.1:8877`; missing and invalid bearer tokens both return `401`.
- Enabled Tailscale Serve on HTTPS 8877 and verified it is tailnet-only. Removed
  the pre-existing Funnel exposure, then restored Hermes and call-me as
  tailnet-only Serve routes.
- Sent one synthetic verification email to the owner's own Gmail account. The
  agent returned the exact fresh Gmail code, archive acknowledgement succeeded,
  and Gmail confirmed the `INBOX` label was removed. The synthetic message was
  then moved to Trash.
- Confirmed the Messages source returns a real recent SMS code without source
  errors.
- Installed, signed, launched, and process-verified the menu-bar app on the
  MacBook. Its `client.json` is mode `600`, and an authenticated health request
  from the MacBook to the Mac mini succeeded over tailnet HTTPS.
- Staged the unpacked Chrome extension on the MacBook. Chrome 151 requires its
  Developer Mode `Load unpacked` picker for final enrollment; remote UI control
  was unavailable, so no protected Chrome preferences were modified.

