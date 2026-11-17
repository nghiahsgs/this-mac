APP = build/Build/Products/Debug/ThisMac.app

.PHONY: test build run clean

test:
	swift test --package-path Packages/ThisMacCore

build:
	xcodegen generate --quiet
	xcodebuild -project ThisMac.xcodeproj -scheme ThisMac -configuration Debug -derivedDataPath build build -quiet

run: build
	open $(APP)

clean:
	rm -rf build ThisMac.xcodeproj
