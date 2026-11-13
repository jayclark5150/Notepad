# ============================================================
#  Notepad — Makefile
#  Target: macOS arm64 (Apple Silicon / M1+)
#
#  Usage:
#    make          — build Notepad.app
#    make run      — build and launch
#    make clean    — remove build artefacts
# ============================================================

APP      = Notepad
BUNDLE   = $(APP).app
BINARY   = $(BUNDLE)/Contents/MacOS/$(APP)
PLIST    = $(BUNDLE)/Contents/Info.plist
ICNS_SRC = Notepad.icns
ICNS_DST = $(BUNDLE)/Contents/Resources/Notepad.icns
SRC      = main.mm
ENTITLE  = Notepad.entitlements
# Set to a Developer ID for a notarizable, distributable build. Ad-hoc (-) works
# only on the build machine; Gatekeeper blocks ad-hoc builds received through any
# quarantine-triggering channel (download, AirDrop, email).
SIGN_ID  = -
# Signing happens in a temp folder: iCloud-synced folders (Desktop, Documents)
# keep re-adding Finder attributes, which codesign rejects as "detritus".
STAGE    = $(patsubst %/,%,$(or $(TMPDIR),/tmp))/notepad-build
STAGED   = $(STAGE)/$(BUNDLE)
COPY     = ditto --norsrc --noextattr --noqtn --noacl

CXX      = clang++
ARCH     = arm64
SDK      = $(shell xcrun --sdk macosx --show-sdk-path)
MIN_VER  = 12.0

CXXFLAGS = -arch $(ARCH) \
           -std=c++17 \
           -fobjc-arc \
           -isysroot $(SDK) \
           -mmacosx-version-min=$(MIN_VER) \
           -Wall -Wextra -O2

LDFLAGS  = -arch $(ARCH) \
           -isysroot $(SDK) \
           -mmacosx-version-min=$(MIN_VER) \
           -framework Cocoa \
           -framework WebKit \
           -framework UniformTypeIdentifiers

.PHONY: all run install dmg clean

all: $(BINARY) $(PLIST) $(ICNS_DST) codesign

$(BUNDLE)/Contents/MacOS:
	mkdir -p $@

$(BINARY): $(SRC) | $(BUNDLE)/Contents/MacOS
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $<
	xattr -c $@

$(ICNS_DST): $(ICNS_SRC) | $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(ICNS_SRC) $@
	xattr -c $@

$(PLIST): Info.plist | $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents
	cp Info.plist $@
	xattr -c $@

.PHONY: codesign
codesign: $(BINARY) $(PLIST) $(ICNS_DST)
	rm -rf "$(STAGE)" && mkdir -p "$(STAGE)"
	$(COPY) $(BUNDLE) "$(STAGED)"
	find "$(STAGED)" \( -name "._*" -o -name ".DS_Store" \) -delete
	xattr -cr "$(STAGED)"
	codesign --force --options runtime --entitlements $(ENTITLE) --sign "$(SIGN_ID)" "$(STAGED)"
	codesign --verify --deep --strict "$(STAGED)"
	rm -rf $(BUNDLE)
	$(COPY) "$(STAGED)" $(BUNDLE)


run: all
	open $(BUNDLE)

install: all
	rm -rf /Applications/$(BUNDLE)
	$(COPY) "$(STAGED)" /Applications/$(BUNDLE)
	@echo "Installed to /Applications/$(BUNDLE)"

dmg: all
	$(eval DMG_DIR := $(shell mktemp -d))
	$(COPY) "$(STAGED)" "$(DMG_DIR)/$(BUNDLE)"
	ln -s /Applications "$(DMG_DIR)/Applications"
	hdiutil create -volname "$(APP)" -srcfolder "$(DMG_DIR)" \
	    -ov -format UDZO -o "$(APP).dmg"
	rm -rf "$(DMG_DIR)"
	@echo "Created $(APP).dmg"

clean:
	rm -rf $(BUNDLE) "$(STAGE)"
