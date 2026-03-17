APP_NAME = Claudblobs
BUNDLE_NAME = Claudblobs.app
BUILD_DIR = .build/release
BUNDLE_DIR = $(BUILD_DIR)/$(BUNDLE_NAME)

.PHONY: build bundle clean run restart stop

build:
	swift build -c release

bundle: build
	rm -rf "$(BUNDLE_DIR)"
	mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	mkdir -p "$(BUNDLE_DIR)/Contents/Resources/hooks"
	cp "$(BUILD_DIR)/Claudblobs" "$(BUNDLE_DIR)/Contents/MacOS/"
	cp Resources/Info.plist "$(BUNDLE_DIR)/Contents/"
	cp Resources/hooks/*.sh "$(BUNDLE_DIR)/Contents/Resources/hooks/"
	chmod +x "$(BUNDLE_DIR)/Contents/Resources/hooks/"*.sh
	swift Resources/generate-icon.swift "$(BUNDLE_DIR)/Contents/Resources/AppIcon.icns"

install: bundle
	cp -R "$(BUNDLE_DIR)" /Applications/
	@echo "Installed to /Applications/$(BUNDLE_NAME)"

clean:
	swift package clean
	rm -rf "$(BUNDLE_DIR)"

run: bundle
	open "$(BUNDLE_DIR)"

stop:
	@pkill -x Claudblobs 2>/dev/null && echo "Stopped Claudblobs" || echo "Claudblobs not running"

restart: bundle stop
	@sleep 0.5
	open "$(BUNDLE_DIR)"
