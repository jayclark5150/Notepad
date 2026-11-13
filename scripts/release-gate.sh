#!/bin/bash
# ============================================================
#  Release regression gate for .github/workflows/release.yml
#  Every check here is listed in regression-checklist.md (IDs match).
#
#  Usage:
#    release-gate.sh pre        <tag>                  repo version checks
#    release-gate.sh asset      <dmg> <version>        DMG contents + signature
#    release-gate.sh cask       <cask.rb>              cask matches the asset name
#    release-gate.sh cask-final <cask.rb> <version> <sha256>
#    release-gate.sh published  <dmg> <sha256>         downloaded asset == expected
#
#  Prints PASS/FAIL/WARN per check (also to $GITHUB_STEP_SUMMARY when set)
#  and exits 1 if any check failed.
# ============================================================
set -u

FAILS=0
summary() { if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then echo "$1" >> "$GITHUB_STEP_SUMMARY"; fi; }
pass()    { echo "PASS  $1"; summary "| PASS | $1 |"; }
fail()    { echo "FAIL  $1"; summary "| **FAIL** | $1 |"; FAILS=$((FAILS + 1)); }
warn()    { echo "WARN  $1"; summary "| WARN | $1 |"; }

sha256_of() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    else sha256sum "$1" | awk '{print $1}'; fi
}

# Value of a <key>…</key><string>…</string> pair; works across line breaks.
plist_value() {
    tr -d '\n' < "$1" | sed -n "s|.*<key>$2</key>[[:space:]]*<string>\([^<]*\)</string>.*|\1|p"
}

stage_pre() {
    local tag="$1" ver="${1#v}"
    if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then pass "R1 tag '$tag' is vX.Y.Z"
    else fail "R1 tag '$tag' is not vX.Y.Z"; fi

    local short build
    short=$(plist_value Info.plist CFBundleShortVersionString)
    build=$(plist_value Info.plist CFBundleVersion)
    [ "$short" = "$ver" ] && pass "R2 Info.plist CFBundleShortVersionString = $ver" \
                          || fail "R2 Info.plist CFBundleShortVersionString is '$short', tag says '$ver'"
    [ "$build" = "$ver" ] && pass "R3 Info.plist CFBundleVersion = $ver" \
                          || fail "R3 Info.plist CFBundleVersion is '$build', tag says '$ver'"

    grep -qF "badge/version-$ver-" README.md && pass "R4 README version badge = $ver" \
                                              || fail "R4 README version badge is not $ver"
    grep -qF "## [$ver]" CHANGELOG.md && pass "R5 CHANGELOG has a [$ver] entry" \
                                      || fail "R5 CHANGELOG has no '## [$ver]' entry"
}

stage_asset() {
    local dmg="$1" ver="$2"
    if [ -s "$dmg" ]; then pass "R7 $dmg exists"; else fail "R7 $dmg missing or empty"; return; fi

    if ! command -v hdiutil >/dev/null 2>&1; then
        if [ "${RELEASE_GATE_ALLOW_SKIP:-0}" = "1" ]; then warn "R8-R12 skipped: not on macOS"
        else fail "R8 hdiutil not available (macOS required)"; fi
        return
    fi

    local mnt; mnt=$(mktemp -d)
    if ! hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$dmg" >/dev/null; then
        fail "R8 DMG does not mount"; rmdir "$mnt"; return
    fi
    pass "R8 DMG mounts"

    local app="$mnt/Notepad.app"
    if [ -d "$app" ]; then pass "R9 DMG contains Notepad.app (cask: app \"Notepad.app\")"
    else fail "R9 DMG has no Notepad.app at its root"; fi

    [ -L "$mnt/Applications" ] && pass "R10 DMG has the Applications shortcut" \
                               || fail "R10 DMG has no Applications shortcut"

    if [ -d "$app" ]; then
        local appver
        appver=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist" 2>/dev/null)
        [ "$appver" = "$ver" ] && pass "R11 app inside DMG is version $ver" \
                               || fail "R11 app inside DMG is version '$appver', expected '$ver'"

        if codesign --verify --deep --strict "$app" 2>/dev/null; then pass "R12 codesign --verify --deep --strict"
        else fail "R12 app signature does not verify"; fi

        if codesign -dv "$app" 2>&1 | grep -q "Signature=adhoc"; then
            warn "W1 app is ad-hoc signed: Gatekeeper blocks it on other Macs (see buildme.md)"
        fi
    fi
    hdiutil detach "$mnt" -quiet || hdiutil detach "$mnt" -force -quiet
    rmdir "$mnt" 2>/dev/null
}

stage_cask() {
    local cask="$1"
    if [ ! -f "$cask" ]; then fail "R13 cask file $cask not found"; return; fi
    grep -qE '^[[:space:]]*url[[:space:]]+".*/download/v#\{version\}/Notepad\.dmg"' "$cask" \
        && pass "R13 cask url downloads v#{version}/Notepad.dmg" \
        || fail "R13 cask url does not point at v#{version}/Notepad.dmg"
    grep -qE '^[[:space:]]*app[[:space:]]+"Notepad\.app"' "$cask" \
        && pass "R14 cask installs Notepad.app" \
        || fail "R14 cask has no app \"Notepad.app\" stanza"
    local nv ns
    nv=$(grep -cE '^[[:space:]]*version[[:space:]]+"' "$cask")
    ns=$(grep -cE '^[[:space:]]*sha256[[:space:]]+"' "$cask")
    [ "$nv" = 1 ] && [ "$ns" = 1 ] && pass "R15 cask has exactly one version and one sha256 line" \
                                   || fail "R15 cask has $nv version and $ns sha256 lines (expected 1 each)"
}

stage_cask_final() {
    local cask="$1" ver="$2" sha="$3"
    grep -qE "^[[:space:]]*version[[:space:]]+\"$ver\"" "$cask" \
        && pass "R16 cask version = $ver" || fail "R16 cask version is not $ver"
    [[ "$sha" =~ ^[0-9a-f]{64}$ ]] && grep -qE "^[[:space:]]*sha256[[:space:]]+\"$sha\"" "$cask" \
        && pass "R17 cask sha256 = $sha" || fail "R17 cask sha256 is not '$sha'"
}

stage_published() {
    local dmg="$1" sha="$2" got
    if [ ! -s "$dmg" ]; then fail "R18 published Notepad.dmg could not be downloaded"; return; fi
    got=$(sha256_of "$dmg")
    [ "$got" = "$sha" ] && pass "R18 published Notepad.dmg sha256 matches ($sha)" \
                        || fail "R18 published Notepad.dmg sha256 is $got, expected $sha"
}

stage="${1:-}"; shift || true
summary "| Result | Check ($stage) |"
summary "|---|---|"
case "$stage" in
    pre)        [ $# -eq 1 ] || { echo "usage: $0 pre <tag>"; exit 2; };                   stage_pre "$@" ;;
    asset)      [ $# -eq 2 ] || { echo "usage: $0 asset <dmg> <version>"; exit 2; };       stage_asset "$@" ;;
    cask)       [ $# -eq 1 ] || { echo "usage: $0 cask <cask.rb>"; exit 2; };              stage_cask "$@" ;;
    cask-final) [ $# -eq 3 ] || { echo "usage: $0 cask-final <cask.rb> <ver> <sha>"; exit 2; }; stage_cask_final "$@" ;;
    published)  [ $# -eq 2 ] || { echo "usage: $0 published <dmg> <sha256>"; exit 2; };    stage_published "$@" ;;
    *) echo "usage: $0 {pre|asset|cask|cask-final|published} ..."; exit 2 ;;
esac
summary ""

if [ "$FAILS" -gt 0 ]; then echo "Gate '$stage': $FAILS check(s) failed"; exit 1; fi
echo "Gate '$stage': all checks passed"
