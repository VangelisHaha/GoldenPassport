# Build outputs live outside ~/Documents: iCloud Drive adds extended attributes
# that make codesign fail, and would also sync hundreds of MB of artifacts.
BUILD_ROOT ?= $(HOME)/Library/Caches/GoldenPassport-build
SWIFT = xcrun swift
SWIFT_FLAGS = --scratch-path "$(BUILD_ROOT)/swiftpm"

.PHONY: test test-native dev release beta run-dev clean

test:
	@if xcrun --sdk macosx --show-sdk-platform-path >/dev/null 2>&1 && xcrun swift --version | grep -Eq 'Swift version ([6-9]|[1-9][0-9])\.'; then \
		$(SWIFT) test $(SWIFT_FLAGS); \
	else \
		echo "当前工具链不支持上游 Swift Testing，运行原生兼容性验收测试。"; \
		BUILD_ROOT="$(BUILD_ROOT)" bash scripts/test-native.sh; \
	fi

test-native:
	BUILD_ROOT="$(BUILD_ROOT)" bash scripts/test-native.sh

dev:
	BUILD_ROOT="$(BUILD_ROOT)" scripts/build-app.sh dev

release:
	BUILD_ROOT="$(BUILD_ROOT)" scripts/build-app.sh release

run-dev: dev
	open "$(BUILD_ROOT)/dev/GoldenPassport Dev.app"

clean:
	rm -rf "$(BUILD_ROOT)"

beta:
	BUILD_ROOT="$(BUILD_ROOT)" scripts/package-beta.sh
