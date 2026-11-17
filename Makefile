APP = build/Build/Products/Debug/ThisMac.app

.PHONY: test build run install clean

test:
	swift test --package-path Packages/ThisMacCore

build:
	xcodegen generate --quiet
	xcodebuild -project ThisMac.xcodeproj -scheme ThisMac -configuration Debug -derivedDataPath build build -quiet

run: build
	open $(APP)

# Builds an optimized copy and puts it in /Applications as "This Mac".
install:
	xcodegen generate --quiet
	xcodebuild -project ThisMac.xcodeproj -scheme ThisMac -configuration Release -derivedDataPath build build -quiet
	rm -rf "/Applications/This Mac.app"
	cp -R build/Build/Products/Release/ThisMac.app "/Applications/This Mac.app"

clean:
	rm -rf build ThisMac.xcodeproj
