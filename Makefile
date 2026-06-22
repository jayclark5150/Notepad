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
SIGN_ID  = -

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
           -framework Cocoa

.PHONY: all run clean

all: $(BINARY) $(PLIST) $(ICNS_DST) codesign

$(BUNDLE)/Contents/MacOS:
	mkdir -p $@

$(BINARY): $(SRC) | $(BUNDLE)/Contents/MacOS
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $<

$(ICNS_DST): $(ICNS_SRC) | $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(ICNS_SRC) $@

$(PLIST): Info.plist | $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents
	cp Info.plist $@

.PHONY: codesign
codesign: $(BINARY) $(PLIST)
	codesign --force --options runtime --entitlements $(ENTITLE) --sign $(SIGN_ID) $(BUNDLE)


run: all
	open $(BUNDLE)

clean:
	rm -rf $(BUNDLE)
