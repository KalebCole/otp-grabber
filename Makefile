.DEFAULT_GOAL := test

PYTHON ?= python3
NPM ?= npm
SWIFT ?= swift

.PHONY: test test-python test-js test-swift

test: test-python test-js test-swift

test-python:
	$(PYTHON) -m unittest discover -s agent/tests -v

test-js:
	$(NPM) run test:extension

test-swift:
	$(SWIFT) test --package-path menubar
