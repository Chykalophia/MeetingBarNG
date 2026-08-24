PROJECT := MeetingBarNG.xcodeproj
SCHEME := MeetingBarNG
XCODEBUILD ?= xcodebuild
SWIFT ?= swift
SWIFTLINT ?= swiftlint
BUILD_DIR ?= build
COVERAGE_DIR := $(BUILD_DIR)/coverage
XCODE_RESULT_BUNDLE := $(COVERAGE_DIR)/MeetingBarNG.xcresult
DERIVED_DATA_DIR := $(BUILD_DIR)/DerivedData
XCODE_SOURCE_PACKAGES_DIR := $(BUILD_DIR)/SourcePackages
HOST_ARCH := $(shell uname -m)
DESTINATION ?= platform=macOS,arch=$(HOST_ARCH)
XCODEBUILD_FLAGS := -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_DIR) -clonedSourcePackagesDirPath $(XCODE_SOURCE_PACKAGES_DIR) -onlyUsePackageVersionsFromResolvedFile
LOCAL_CODESIGN_FLAGS := CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# Local self-signed re-sign so macOS TCC grants (Calendar, Reminders, Camera/Mic)
# PERSIST across rebuilds. The xcodebuild build stays unsigned (avoids the
# DEVELOPMENT_TEAM / dependency-target entitlement problems); afterwards the built
# .app bundle is re-signed with a stable local identity + a profile-free
# entitlements set (XCConfig/LocalSigning.entitlements — the app's entitlements
# minus the Apple-profile-gated time-sensitive-notifications key). Without a
# stable signature every rebuild changes the binary and macOS invalidates the
# prior grant, so the app reads as "granted" while EventKit returns nothing.
#   make run-local                 # build + sign + launch
#   make sign-local                # re-sign the already-built app
LOCAL_SIGN_IDENTITY ?= MeetingBarNG-Local
LOCAL_APP := $(DERIVED_DATA_DIR)/Build/Products/Debug/MeetingBarNG.app
LOGIC_COVERAGE_SOURCES := MeetingBarNG/Calendar MeetingBarNG/Meetings MeetingBarNG/Notifications MeetingBarNG/UI/StatusBar MeetingBarNG/Utilities/Diagnostics

# Pipe xcodebuild through xcbeautify when available; otherwise grep for the lines that matter.
XCFILTER := $(shell command -v xcbeautify >/dev/null 2>&1 && echo 'xcbeautify --quiet --renderer terminal' || echo "grep -E '(error:|warning:|FAIL|PASS|\\*\\* )'")
# Append a JUnit report to app-hosted test runs when xcbeautify is available.
JUNIT_REPORT := $(shell command -v xcbeautify >/dev/null 2>&1 && echo '--report junit --report-path $(BUILD_DIR)/test-results')

.PHONY: build build-quiet build-release test test-quiet test-app test-app-quiet test-logic test-logic-quiet coverage coverage-report coverage-logic-report coverage-app-report coverage-gate test-summary coverage-codecov lint lint-fix open validate-strings lint-strings sign-local run-local archive export-app dmg notarize release-local

# ---------------------------------------------------------------------------
# Distribution (Developer ID / direct download)
#
# CI does this on a tag push — see .github/workflows/release.yml. These targets
# exist so the same pipeline can be driven locally when CI is not an option, or
# to debug a signing failure without burning a 20-minute Actions run each time.
#
#   make release-local            # archive -> export -> dmg -> notarize
#
# Needs a "Developer ID Application" certificate in the login keychain, and for
# notarization: AC_APPLE_ID, AC_PASSWORD (app-specific), AC_TEAM_ID.
# ---------------------------------------------------------------------------
VERSION := $(shell grep -m1 'MARKETING_VERSION' $(PROJECT)/project.pbxproj | sed 's/.*= *//;s/;//')
ARCHIVE_PATH := $(BUILD_DIR)/MeetingBarNG.xcarchive
EXPORT_PATH := $(BUILD_DIR)/export
EXPORTED_APP := $(EXPORT_PATH)/MeetingBarNG.app
DMG_PATH := $(BUILD_DIR)/MeetingBarNG-$(VERSION).dmg

# Signed with the FULL entitlements only when a provisioning profile is available;
# otherwise the time-sensitive-notifications key has to go, or signing fails.
# Override with: make archive RELEASE_ENTITLEMENTS=MeetingBarNG/MeetingBarNG.entitlements PROFILE_SPECIFIER="<profile name>"
RELEASE_ENTITLEMENTS ?= XCConfig/DeveloperID.entitlements
PROFILE_SPECIFIER ?=

archive:
	@mkdir -p $(BUILD_DIR)
	@echo "==> Archiving $(SCHEME) $(VERSION) for Developer ID"
	$(XCODEBUILD) archive \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=macOS' \
		-archivePath $(ARCHIVE_PATH) \
		-derivedDataPath $(DERIVED_DATA_DIR) \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY="Developer ID Application" \
		CODE_SIGN_ENTITLEMENTS="$(RELEASE_ENTITLEMENTS)" \
		PROVISIONING_PROFILE_SPECIFIER="$(PROFILE_SPECIFIER)" \
		ENABLE_HARDENED_RUNTIME=YES \
		OTHER_CODE_SIGN_FLAGS="--timestamp"

export-app: archive
	@rm -rf $(EXPORT_PATH)
	$(XCODEBUILD) -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportOptionsPlist XCConfig/ExportOptions-DeveloperID.plist \
		-exportPath $(EXPORT_PATH)
	@echo "==> Verifying signature"
	codesign --verify --deep --strict --verbose=2 "$(EXPORTED_APP)"
	@codesign -d --verbose=2 "$(EXPORTED_APP)" 2>&1 | grep -q "flags=.*runtime" \
		|| { echo "ERROR: hardened runtime missing — notarization would reject this."; exit 1; }

dmg: export-app
	@chmod +x Scripts/package-dmg.sh
	Scripts/package-dmg.sh "$(EXPORTED_APP)" "$(VERSION)" "$(DMG_PATH)"
	codesign --force --sign "Developer ID Application" --timestamp "$(DMG_PATH)"
	codesign --verify --verbose=2 "$(DMG_PATH)"

notarize:
	@chmod +x Scripts/notarize.sh
	Scripts/notarize.sh "$(DMG_PATH)"

release-local: dmg notarize
	@shasum -a 256 "$(DMG_PATH)"
	@echo "==> Ready: $(DMG_PATH)"

sign-local:
	@if ! security find-identity -p codesigning 2>/dev/null | grep -q "$(LOCAL_SIGN_IDENTITY)"; then \
		echo "No code-signing identity '$(LOCAL_SIGN_IDENTITY)' found. Create a self-signed"; \
		echo "Code Signing certificate in Keychain Access (Certificate Assistant ->"; \
		echo "Create a Certificate -> Self-Signed Root -> Code Signing), or override"; \
		echo "LOCAL_SIGN_IDENTITY=<name>."; \
		exit 1; \
	fi
	codesign --force --deep --sign "$(LOCAL_SIGN_IDENTITY)" \
		--entitlements XCConfig/LocalSigning.entitlements "$(LOCAL_APP)"
	codesign --verify --deep --strict --verbose=2 "$(LOCAL_APP)"

run-local: build sign-local
	open "$(LOCAL_APP)"

build:
	@mkdir -p $(BUILD_DIR)
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) -configuration Debug build $(LOCAL_CODESIGN_FLAGS)

build-quiet:
	@mkdir -p $(BUILD_DIR)
	@set -o pipefail; $(XCODEBUILD) $(XCODEBUILD_FLAGS) -configuration Debug build $(LOCAL_CODESIGN_FLAGS) 2>&1 | $(XCFILTER)

build-release:
	@mkdir -p $(BUILD_DIR)
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) -configuration Release build

test: test-logic test-app

test-quiet: test-logic-quiet test-app-quiet

test-app:
	@mkdir -p $(COVERAGE_DIR)
	@rm -rf $(XCODE_RESULT_BUNDLE)
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) -configuration Debug -enableCodeCoverage YES -resultBundlePath $(XCODE_RESULT_BUNDLE) build test $(LOCAL_CODESIGN_FLAGS)
	@$(MAKE) --no-print-directory coverage-app-report

test-app-quiet:
	@mkdir -p $(COVERAGE_DIR) $(BUILD_DIR)/test-results
	@rm -rf $(XCODE_RESULT_BUNDLE)
	@set -o pipefail; $(XCODEBUILD) $(XCODEBUILD_FLAGS) -configuration Debug -enableCodeCoverage YES -resultBundlePath $(XCODE_RESULT_BUNDLE) build test $(LOCAL_CODESIGN_FLAGS) 2>&1 | $(XCFILTER) $(JUNIT_REPORT)
	@$(MAKE) --no-print-directory coverage-app-report

test-logic:
	$(SWIFT) test --enable-code-coverage
	@$(MAKE) --no-print-directory coverage-logic-report

test-logic-quiet:
	$(SWIFT) test --enable-code-coverage --quiet
	@$(MAKE) --no-print-directory coverage-logic-report

coverage: test

coverage-report: coverage-logic-report coverage-app-report

coverage-logic-report:
	@PROFILE="$$(ls -d .build/*/debug/codecov/default.profdata .build/debug/codecov/default.profdata 2>/dev/null | head -n 1)" ; \
	TEST_BINARY="$$(ls -d .build/*/debug/MeetingBarLogicPackageTests.xctest/Contents/MacOS/MeetingBarLogicPackageTests .build/debug/MeetingBarLogicPackageTests.xctest/Contents/MacOS/MeetingBarLogicPackageTests 2>/dev/null | head -n 1)" ; \
	if [ ! -f "$$PROFILE" ] || [ ! -x "$$TEST_BINARY" ]; then \
		echo "SwiftPM coverage is unavailable. Run 'make test-logic' first."; \
		exit 1; \
	fi ; \
	echo "" ; \
	echo "SwiftPM hostless coverage (source files only):" ; \
	xcrun llvm-cov report "$$TEST_BINARY" -instr-profile "$$PROFILE" $(LOGIC_COVERAGE_SOURCES)

coverage-gate:
	@PROFILE="$$(ls -d .build/*/debug/codecov/default.profdata .build/debug/codecov/default.profdata 2>/dev/null | head -n 1)" ; \
	TEST_BINARY="$$(ls -d .build/*/debug/MeetingBarLogicPackageTests.xctest/Contents/MacOS/MeetingBarLogicPackageTests .build/debug/MeetingBarLogicPackageTests.xctest/Contents/MacOS/MeetingBarLogicPackageTests 2>/dev/null | head -n 1)" ; \
	if [ ! -f "$$PROFILE" ] || [ ! -x "$$TEST_BINARY" ]; then \
		echo "SwiftPM coverage data not found. Run 'make test-logic' first."; \
		exit 1; \
	fi ; \
	COVERAGE=$$(xcrun llvm-cov report "$$TEST_BINARY" -instr-profile "$$PROFILE" $(LOGIC_COVERAGE_SOURCES) 2>/dev/null | tail -1 | awk '{print $$4}' | tr -d '%') ; \
	echo "" ; \
	echo "Logic coverage gate (threshold: 90%):" ; \
	awk -v cov="$$COVERAGE" 'BEGIN { if (cov + 0 < 90.0) { print "  NOTE: " cov "% is below 90% target (gate is reporting-only)" } else { print "  PASS: " cov "% meets 90% target" } }'

coverage-app-report:
	@if [ ! -d "$(XCODE_RESULT_BUNDLE)" ]; then \
		echo "Xcode coverage is unavailable. Run 'make test' or 'make test-quiet' first."; \
		exit 1; \
	fi
	@echo ""
	@echo "Xcode app-hosted coverage (target summary):"
	@set -o pipefail; xcrun xccov view --report --only-targets $(XCODE_RESULT_BUNDLE) 2>/dev/null | awk 'NR <= 2 || /MeetingBarNG\.app/'

lint:
	@if command -v $(SWIFTLINT) >/dev/null 2>&1; then \
		$(SWIFTLINT); \
	else \
		echo "SwiftLint is not installed. Install it from https://github.com/realm/SwiftLint"; \
		exit 1; \
	fi

lint-fix:
	@if command -v $(SWIFTLINT) >/dev/null 2>&1; then \
		$(SWIFTLINT) --fix; \
		$(SWIFTLINT); \
	else \
		echo "SwiftLint is not installed. Install it from https://github.com/realm/SwiftLint"; \
		exit 1; \
	fi

open:
	open $(PROJECT)

validate-strings:
	@bash Scripts/validate_localizations.sh

# Two-way English key check: nothing used-but-undefined, nothing defined-but-orphaned.
lint-strings:
	@bash Scripts/strings-lint

test-summary:
	@bash Scripts/test_summary.sh $(XCODE_RESULT_BUNDLE)

# Generate a Cobertura coverage report from the app-hosted test build for
# Codecov. Uses slather against our custom derived-data path; skips cleanly
# (rather than failing) when slather is not installed locally.
coverage-codecov:
	@mkdir -p $(COVERAGE_DIR)
	@if command -v slather >/dev/null 2>&1; then \
		slather coverage --scheme $(SCHEME) --cobertura-xml --build-directory $(DERIVED_DATA_DIR) --output-directory $(COVERAGE_DIR) $(PROJECT) ; \
	else echo "slather not installed; skipping cobertura. Install with: gem install slather" ; fi
