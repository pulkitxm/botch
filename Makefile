SELECTED_DEV_DIR := $(shell xcode-select -p 2>/dev/null)
ifneq ($(wildcard $(SELECTED_DEV_DIR)/usr/bin/xcodebuild),)
  DEVELOPER_DIR := $(SELECTED_DEV_DIR)
else
  DEVELOPER_DIR := $(firstword $(wildcard /Applications/Xcode*.app/Contents/Developer))
endif
export DEVELOPER_DIR

SWIFT_FILES := Sources Tests Package.swift

.PHONY: build test lint format app icon clean

build:
	swift build

test:
	swift test

lint:
	swift format lint --strict --recursive $(SWIFT_FILES)

format:
	swift format --in-place --recursive $(SWIFT_FILES)

app:
	scripts/bundle.sh

icon:
	swift scripts/icon.swift AppIcon.iconset
	iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
	rm -rf AppIcon.iconset

clean:
	rm -rf .build dist
