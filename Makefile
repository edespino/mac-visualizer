DERIVED := DerivedData
PROJECT := MacVisualizer.xcodeproj
SCHEME  := MacVisualizer
DEST    := platform=macOS

.PHONY: generate build test run clean

generate:
	xcodegen generate

build: generate
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' -derivedDataPath $(DERIVED)

test: generate
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' -derivedDataPath $(DERIVED)

run: build
	open $(DERIVED)/Build/Products/Debug/MacVisualizer.app

clean:
	rm -rf $(PROJECT) $(DERIVED)
