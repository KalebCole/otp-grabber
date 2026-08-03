.DEFAULT_GOAL := test

PYTHON ?= python3.11
NPM ?= npm
SWIFT ?= swift

.PHONY: test test-python test-js test-swift check package

test: test-python test-js test-swift

test-python:
	$(PYTHON) -m unittest discover -s agent/tests -v

test-js:
	$(NPM) test

test-swift:
	$(SWIFT) test --package-path menubar
	$(SWIFT) run --package-path menubar OTPGrabberMenuBarChecks

check:
	bash scripts/check-repository.sh
	node .github/skills/impeccable/scripts/detect.mjs docs/ --json

package:
	scripts/package-release.sh
