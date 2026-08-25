SWIFT ?= swift
SIMULATOR ?= platform=iOS Simulator,name=iPhone 17 Pro
APP_BUNDLE_ID ?= com.github.namuan.personalreader
DEVICE_BUILD_DIR ?= DerivedData/Device
DEVICE_ID ?= $(shell xcodebuild -project PersonalReaderApp.xcodeproj -scheme PersonalReaderApp -showdestinations 2>/dev/null | sed -n 's/.*{ platform:iOS,[^}]*id:\([^,}]*\),.*/\1/p' | grep -v placeholder | head -1)
TEAM_ID ?= $(shell TEAM=$$(ls -t ~/Library/Developer/Xcode/UserData/Capabilities/capabilities-*-*-bundle.json 2>/dev/null | sed -E 's/.*-([A-Z0-9]{10})-bundle\.json/\1/' | head -1); if [ -n "$$TEAM" ]; then echo "$$TEAM"; else security find-identity -v -p codesigning 2>/dev/null | awk -F'[()]' '/Apple Development:/{gsub(/^[ \t]+|[ \t]+$$/, "", $$3); print $$3; exit}'; fi)
DEVICE_APP_PATH = $(DEVICE_BUILD_DIR)/Build/Products/Debug-iphoneos/PersonalReaderApp.app

.PHONY: help resolve build release test lint format check project app-build app-install device-install update dependencies clean reset open

help:
	@printf '%s\n' \
		'make resolve       Resolve Swift package dependencies' \
		'make build         Build the package in debug mode' \
		'make release       Build the package in release mode' \
		'make test          Run all tests' \
		'make lint          Check Swift formatting' \
		'make format        Format Swift sources in place' \
		'make check         Run lint, build, and tests' \
		'make project       (Re)generate PersonalReaderApp.xcodeproj with XcodeGen' \
		'make app-build     Build the iOS app for the simulator' \
		'make app-install   Install and launch the app on a booted simulator' \
		'make device-install Build, install, and launch on a connected iPhone' \
		'make update        Update Swift package dependencies' \
		'make dependencies  Show resolved dependency graph' \
		'make clean         Remove SwiftPM build artifacts' \
		'make reset         Remove build artifacts and Package.resolved' \
		'make open          Open the package in Xcode'

resolve:
	$(SWIFT) package resolve

build:
	$(SWIFT) build

release:
	$(SWIFT) build -c release

test:
	$(SWIFT) test

lint:
	$(SWIFT) format lint --recursive --parallel --strict Sources Tests Package.swift App AppTests

format:
	$(SWIFT) format format --in-place --recursive --parallel Sources Tests Package.swift App AppTests

check: lint build test

project:
	xcodegen generate

app-build:
	xcodebuild -project PersonalReaderApp.xcodeproj -scheme PersonalReaderApp \
		-destination '$(SIMULATOR)' build

app-install:
	xcodebuild -project PersonalReaderApp.xcodeproj -scheme PersonalReaderApp \
		-destination '$(SIMULATOR)' build
	@APP=$$(find ~/Library/Developer/Xcode/DerivedData/PersonalReaderApp-*/Build/Products/Debug-iphonesimulator -maxdepth 1 -name PersonalReaderApp.app | head -1); \
	xcrun simctl install booted "$$APP"; \
	xcrun simctl launch booted $(APP_BUNDLE_ID)

device-install: project
	@test -n "$(DEVICE_ID)" || { echo 'No connected iPhone found. Connect and unlock it, then retry.'; exit 1; }
	@test -n "$(TEAM_ID)" || { echo 'No Xcode development team found. Add your Apple ID in Xcode Settings > Accounts, then retry.'; exit 1; }
	@printf 'Device: %s\nTeam: %s\nBundle: %s\n' '$(DEVICE_ID)' '$(TEAM_ID)' '$(APP_BUNDLE_ID)'
	xcodebuild -project PersonalReaderApp.xcodeproj -scheme PersonalReaderApp \
		-configuration Debug \
		-destination 'platform=iOS,id=$(DEVICE_ID)' \
		-derivedDataPath '$(DEVICE_BUILD_DIR)' \
		-allowProvisioningUpdates \
		-allowProvisioningDeviceRegistration \
		DEVELOPMENT_TEAM='$(TEAM_ID)' \
		PRODUCT_BUNDLE_IDENTIFIER='$(APP_BUNDLE_ID)' \
		build
	xcrun devicectl device install app --device '$(DEVICE_ID)' '$(DEVICE_APP_PATH)'
	xcrun devicectl device process launch --terminate-existing --device '$(DEVICE_ID)' '$(APP_BUNDLE_ID)'

update:
	$(SWIFT) package update

dependencies:
	$(SWIFT) package show-dependencies

clean:
	$(SWIFT) package clean
	rm -rf .build

reset: clean
	rm -f Package.resolved

open:
	open Package.swift
