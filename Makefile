# Shortcuts for the commands in CLAUDE.md and for testing Android Auto. `make help` lists them.

# The device for run-android; empty picks the one adb has connected.
DEVICE ?=
ANDROID_SDK ?= $(or $(ANDROID_HOME),$(ANDROID_SDK_ROOT),$(HOME)/Android/Sdk)
DHU ?= $(ANDROID_SDK)/extras/google/auto/desktop-head-unit
EMULATOR ?= $(ANDROID_SDK)/emulator/emulator

.DEFAULT_GOAL := help
.PHONY: help get gen format format-check analyze test check run car-preview run-android devices apk pair-qr pair connect dhu emulator

help: ## Lists the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

get: ## Fetches the packages
	flutter pub get

gen: get ## Generates the drift code
	dart run build_runner build --delete-conflicting-outputs

format: ## Formats the code
	dart format .

format-check: ## Fails on unformatted code, as CI does
	dart format --output=none --set-exit-if-changed .

analyze: ## Runs the analyzer, which must report nothing
	flutter analyze --fatal-infos

test: ## Runs the tests; TEST=test/car_library_test.dart runs one file
	flutter test $(TEST)

check: format-check analyze test ## Runs what CI checks

run: ## Runs the app on Linux
	flutter run -d linux

car-preview: ## Runs the app on Linux, opening on a preview of what Android Auto shows
	flutter run -d linux --dart-define=PUFFER_CAR_PREVIEW=true

run-android: ## Runs the app on the Android device adb has connected; DEVICE=<id> picks one of several
	@device="$(DEVICE)"; \
	if [ -z "$$device" ]; then \
	  count=$$(adb devices | awk 'NR > 1 && $$2 == "device"' | wc -l); \
	  if [ "$$count" -eq 0 ]; then echo "No Android device connected: make connect ADDR=<ip:port>"; exit 1; fi; \
	  if [ "$$count" -gt 1 ]; then echo "Several devices connected; pick one with DEVICE=<id>:"; adb devices -l; exit 1; fi; \
	  device=$$(adb get-serialno); \
	fi; \
	echo "flutter run -d $$device"; \
	flutter run -d "$$device"

devices: ## Lists the devices Flutter and adb see
	flutter devices
	adb devices -l

apk: ## Builds the release APKs, one per ABI
	flutter build apk --release --split-per-abi

pair-qr: ## Pairs a phone for wireless debugging with a QR code
	tool/adb-pair-qr.sh

pair: ## Pairs a phone with a pairing code: make pair ADDR=<ip:port>
	@test -n "$(ADDR)" || { echo "Usage: make pair ADDR=<ip:port from Pair device with pairing code>"; exit 1; }
	adb pair $(ADDR)

connect: ## Connects to a paired phone: make connect ADDR=<ip:port>
	@test -n "$(ADDR)" || { echo "Usage: make connect ADDR=<ip:port shown under Wireless debugging>"; exit 1; }
	adb connect $(ADDR)

dhu: ## Opens the Android Auto Desktop Head Unit; start the head unit server on the device first
	@test -x "$(DHU)" || { echo "No head unit at $(DHU). Install it: sdkmanager \"extras;google;auto\""; exit 1; }
	adb forward tcp:5277 tcp:5277
	cd "$(dir $(DHU))" && ./desktop-head-unit

emulator: ## Starts an emulator: make emulator AVD=<name>; without AVD, lists them
	@if [ -z "$(AVD)" ]; then "$(EMULATOR)" -list-avds; else "$(EMULATOR)" -avd "$(AVD)" & fi
