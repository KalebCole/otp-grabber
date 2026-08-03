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
