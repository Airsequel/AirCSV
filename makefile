.PHONY: help
help: makefile
	@tail -n +4 makefile | grep ".PHONY"


PROJECT     = AirCSV/AirCSV.xcodeproj
SCHEME      = AirCSV
BUILD_DIR   = .build
APP         = $(BUILD_DIR)/Build/Products/Release/AirCSV.app
USE_NATIVE_TABLE ?=
SWIFT_ACTIVE_COMPILATION_CONDITIONS ?= $(if $(USE_NATIVE_TABLE),USE_NATIVE_TABLE,)
# Local builds only compile the active architecture; `make install`
# overrides this to build a universal binary.
ONLY_ACTIVE_ARCH ?= YES


.PHONY: build  # Pass USE_NATIVE_TABLE=1 to use native SwiftUI Table
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release -derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		ONLY_ACTIVE_ARCH=$(ONLY_ACTIVE_ARCH) \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS="$(SWIFT_ACTIVE_COMPILATION_CONDITIONS)"


.PHONY: test
test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=macOS' -derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS="$(SWIFT_ACTIVE_COMPILATION_CONDITIONS)"


.PHONY: dev  # Build and launch AirCSV.app with csvs/example.csv
dev: build
	"$(APP)/Contents/MacOS/AirCSV" csvs/example.csv


.PHONY: format
format:
	@which swift-format > /dev/null 2>&1 \
		&& swift-format -i -r AirCSV/AirCSV/ \
		|| echo "swift-format not found (brew install swift-format)"


.PHONY: install  # Install AirCSV.app (universal binary) to /Applications
install: ONLY_ACTIVE_ARCH = NO
install: build
	cp -R "$(APP)" /Applications/


.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)
