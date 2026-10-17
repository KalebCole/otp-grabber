.DEFAULT_GOAL := test

SWIFT ?= swift

.PHONY: test test-swift check package

test: test-swift

test-swift:
	$(SWIFT) test --package-path menubar

check:
	bash scripts/check-repository.sh

package:
	scripts/package-release.sh
