.PHONY: app test clean

ifneq (,$(wildcard /Applications/Xcode-beta.app/Contents/Developer))
DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
export DEVELOPER_DIR
endif

app:
	./scripts/package.sh

test:
	swift test --disable-sandbox

clean:
	swift package clean
	rm -rf dist
