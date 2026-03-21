APP_NAME = ClaudeBlobs
BUNDLE_NAME = ClaudeBlobs.app
BUILD_DIR = .build/release
DEBUG_BUILD_DIR = .build/debug
BUNDLE_DIR = $(BUILD_DIR)/$(BUNDLE_NAME)
DEBUG_BUNDLE_DIR = $(DEBUG_BUILD_DIR)/$(BUNDLE_NAME)

.PHONY: build build-debug bundle bundle-debug clean run restart restart-dev stop release

build:
	swift build -c release

build-debug:
	swift build

bundle: build
	rm -rf "$(BUNDLE_DIR)"
	mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	mkdir -p "$(BUNDLE_DIR)/Contents/Resources/hooks"
	mkdir -p "$(BUNDLE_DIR)/Contents/Resources/opencode-plugin"
	cp "$(BUILD_DIR)/ClaudeBlobs" "$(BUNDLE_DIR)/Contents/MacOS/"
	cp Resources/Info.plist "$(BUNDLE_DIR)/Contents/"
	cp Resources/hooks/*.sh "$(BUNDLE_DIR)/Contents/Resources/hooks/"
	chmod +x "$(BUNDLE_DIR)/Contents/Resources/hooks/"*.sh
	cp Resources/opencode-plugin/claudeblobs-opencode.js "$(BUNDLE_DIR)/Contents/Resources/opencode-plugin/"
	swift Resources/generate-icon.swift "$(BUNDLE_DIR)/Contents/Resources/AppIcon.icns"

bundle-debug: build-debug
	rm -rf "$(DEBUG_BUNDLE_DIR)"
	mkdir -p "$(DEBUG_BUNDLE_DIR)/Contents/MacOS"
	mkdir -p "$(DEBUG_BUNDLE_DIR)/Contents/Resources/hooks"
	cp "$(DEBUG_BUILD_DIR)/ClaudeBlobs" "$(DEBUG_BUNDLE_DIR)/Contents/MacOS/"
	cp Resources/Info.plist "$(DEBUG_BUNDLE_DIR)/Contents/"
	cp Resources/hooks/*.sh "$(DEBUG_BUNDLE_DIR)/Contents/Resources/hooks/"
	chmod +x "$(DEBUG_BUNDLE_DIR)/Contents/Resources/hooks/"*.sh
	swift Resources/generate-icon.swift "$(DEBUG_BUNDLE_DIR)/Contents/Resources/AppIcon.icns"

install: bundle
	cp -R "$(BUNDLE_DIR)" /Applications/
	@echo "Installed to /Applications/$(BUNDLE_NAME)"

clean:
	swift package clean
	rm -rf "$(BUNDLE_DIR)"

run: bundle
	open "$(BUNDLE_DIR)"

stop:
	@pkill -x ClaudeBlobs 2>/dev/null && echo "Stopped ClaudeBlobs" || echo "ClaudeBlobs not running"

restart: bundle stop
	@sleep 0.5
	open "$(BUNDLE_DIR)"

restart-dev: bundle-debug stop
	@sleep 0.5
	open "$(DEBUG_BUNDLE_DIR)"

release:
	@scripts/release.sh $(BUMP)
