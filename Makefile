APP_NAME   := OllamaBar
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
PREFIX     ?= /Applications
CONFIG     ?= release
ARCH_FLAGS ?=
SWIFT      ?= swift
FORMAT     ?= xcrun swift-format

.PHONY: all build install uninstall run test lint format release-zip clean

all: build

build:
	$(SWIFT) build -c $(CONFIG) $(ARCH_FLAGS)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp resources/Info.plist "$(APP)/Contents/Info.plist"
	cp -R resources/en.lproj resources/th.lproj "$(APP)/Contents/Resources/"
	cp "$$($(SWIFT) build -c $(CONFIG) $(ARCH_FLAGS) --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	codesign --force --sign - "$(APP)" 2>/dev/null || true
	@echo "Built $(APP)"

install: build
	rm -rf "$(PREFIX)/$(APP_NAME).app"
	cp -R "$(APP)" "$(PREFIX)/"
	codesign --force --sign - "$(PREFIX)/$(APP_NAME).app" 2>/dev/null || true
	@echo "Installed to $(PREFIX)/$(APP_NAME).app"

uninstall:
	rm -rf "$(PREFIX)/$(APP_NAME).app"
	@echo "Removed $(PREFIX)/$(APP_NAME).app"

run: build
	open "$(APP)"

test:
	$(SWIFT) test

lint:
	$(FORMAT) lint --configuration .swift-format --recursive Sources
	perl scripts/check-strings.pl resources/en.lproj/Localizable.strings resources/th.lproj/Localizable.strings

format:
	$(FORMAT) format --in-place --configuration .swift-format --recursive Sources

release-zip:
	$(MAKE) build ARCH_FLAGS="--arch arm64 --arch x86_64"
	cd "$(BUILD_DIR)" && xattr -cr "$(APP_NAME).app" || true
	cd "$(BUILD_DIR)" && ditto -c -k --norsrc --keepParent "$(APP_NAME).app" "$(APP_NAME).app.zip"
	cd "$(BUILD_DIR)" && shasum -a 256 "$(APP_NAME).app.zip" | tee "$(APP_NAME).app.zip.sha256"

clean:
	rm -rf "$(BUILD_DIR)" .build
