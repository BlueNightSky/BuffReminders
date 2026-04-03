#!/usr/bin/env bash
# Fetch external libraries for local development.
# The release packager handles this via .pkgmeta externals;
# this script replicates that for local dev/testing.
# All libraries are fetched in parallel.

set -euo pipefail

LIBS_DIR="Libs"
mkdir -p "$LIBS_DIR"
pids=()

fetch_svn() {
    local dir="$1" url="$2"
    rm -rf "$LIBS_DIR/$dir"
    if ! svn export --quiet "$url" "$LIBS_DIR/$dir"; then
        echo "  FAILED: $dir"
        return 1
    fi
    echo "  $dir"
}

fetch_git() {
    local dir="$1" url="$2" subdir="${3:-}"
    rm -rf "$LIBS_DIR/$dir"
    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN
    git clone --depth 1 --quiet "$url" "$tmp/repo"
    if [ -n "$subdir" ]; then
        cp -r "$tmp/repo/$subdir" "$LIBS_DIR/$dir"
    else
        mkdir -p "$LIBS_DIR/$dir"
        find "$tmp/repo" -maxdepth 1 \( -name '*.lua' -o -name '*.xml' -o -name '*.toc' \) -exec cp {} "$LIBS_DIR/$dir/" \;
    fi
    echo "  $dir"
}

echo "Fetching libraries..."

# CurseForge SVN
fetch_svn "LibStub"             "https://repos.curseforge.com/wow/libstub/trunk" &
pids+=($!)
fetch_svn "CallbackHandler-1.0" "https://repos.curseforge.com/wow/callbackhandler/trunk/CallbackHandler-1.0" &
pids+=($!)
fetch_svn "AceDB-3.0"           "https://repos.curseforge.com/wow/ace3/trunk/AceDB-3.0" &
pids+=($!)
fetch_svn "LibSharedMedia-3.0"  "https://repos.curseforge.com/wow/libsharedmedia-3-0/trunk/LibSharedMedia-3.0" &
pids+=($!)
fetch_svn "LibDBIcon-1.0"       "https://repos.curseforge.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0" &
pids+=($!)

# GitHub
fetch_git "LibDataBroker-1.1"   "https://github.com/tekkub/libdatabroker-1-1.git" &
pids+=($!)
fetch_git "LibCustomGlow-1.0"   "https://github.com/Stanzilla/LibCustomGlow.git" &
pids+=($!)
fetch_git "LibDualSpec-1.0"     "https://github.com/Adirelle/LibDualSpec-1.0.git" &
pids+=($!)
fetch_git "LibSpecialization"    "https://github.com/BigWigsMods/LibSpecialization.git" "LibSpecialization" &
pids+=($!)

failed=0
for pid in "${pids[@]}"; do
    wait "$pid" || ((failed++))
done

if [ "$failed" -gt 0 ]; then
    echo "ERROR: $failed library fetch(es) failed."
    exit 1
fi

echo "Done."
