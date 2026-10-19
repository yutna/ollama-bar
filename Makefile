APP_NAME   := OllamaBar
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
PREFIX     ?= /Applications
SWIFTC     ?= swiftc

.PHONY: build install uninstall run clean

build:
	mkdir -p "$(APP)/Contents/MacOS"
	cp resources/Info.plist "$(APP)/Contents/Info.plist"
	$(SWIFTC) -O -swift-version 5 Sources/main.swift -o "$(APP)/Contents/MacOS/$(APP_NAME)"
	codesign --force --sign - "$(APP)" 2>/dev/null || true
	@echo "Built $(APP)"

install: build
	rm -rf "$(PREFIX)/$(APP_NAME).app"
	cp -R "$(APP)" "$(PREFIX)/"
	codesign --force --sign - "$(PREFIX)/$(APP_NAME).app" 2>/dev/null || true
	@echo "Installed to $(PREFIX)/$(APP_NAME).app"

run: build
	open "$(APP)"

uninstall:
	rm -rf "$(PREFIX)/$(APP_NAME).app"
	@echo "Removed $(PREFIX)/$(APP_NAME).app"

clean:
	rm -rf "$(BUILD_DIR)"
