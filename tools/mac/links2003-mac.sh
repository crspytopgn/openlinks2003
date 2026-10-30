#!/bin/bash
# Play the original Links 2003 on a Mac, installed from your own disc images.
#
#   tools/mac/links2003-mac.sh setup [--discs DIR] [--cd1 IMG --cd2 IMG --cd3 IMG] [--patch EXE]
#   tools/mac/links2003-mac.sh play [--launcher]   # or open "~/Applications/Links 2003.app"
#   tools/mac/links2003-mac.sh winecfg             # Wine settings for the game's prefix
#
# `setup` downloads a pinned Wine build (Gcenx's macOS builds of WineHQ), turns
# each disc image into a virtual CD, runs the game's own SETUP.EXE and the
# 1.07 patch in a private Wine prefix, and makes "Links 2003.app". Nothing is
# downloaded apart from Wine; the game comes only from the images you point
# it at. See tools/mac/README.md.
#
# Environment:
#   LINKS2003_HOME  where everything goes (default ~/Games/Links2003)
#   LINKS2003_WINE  use this wine binary instead of downloading one
#   LINKS2003_APP   where to put the app (default ~/Applications/Links 2003.app)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDIMAGE="$HERE/../cdimage/cdimage.py"

WINE_VERSION="11.20"
WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/$WINE_VERSION/wine-devel-$WINE_VERSION-osx64.tar.xz"
WINE_SHA256="33bbe09ac5d867d75d6d3aef23b66d25ff81cb62c33bc3f405c138bbf7195ad7"

BASE="${LINKS2003_HOME:-$HOME/Games/Links2003}"
APP="${LINKS2003_APP:-$HOME/Applications/Links 2003.app}"
DEFAULT_DISCS="/Volumes/nvme.fanxiang/Claude/links2003/gameiso"
export WINEPREFIX="$BASE/prefix"
export WINEDEBUG="${WINEDEBUG:--all}"

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

find_wine() {
	if [ -n "${LINKS2003_WINE:-}" ]; then
		WINE="$LINKS2003_WINE"
	else
		WINE="$BASE/wine/Wine Devel.app/Contents/Resources/wine/bin/wine"
	fi
	WINESERVER="$(dirname "$WINE")/wineserver"
}

install_wine() {
	find_wine
	if [ -x "$WINE" ]; then
		return
	fi
	if [ "$(uname -m)" = arm64 ] && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
		say "Installing Rosetta 2 (Wine runs the game as Intel code)"
		softwareupdate --install-rosetta --agree-to-license
	fi
	say "Downloading Wine $WINE_VERSION (about 225 MB)"
	mkdir -p "$BASE/wine"
	local tarball="$BASE/wine/wine.tar.xz"
	curl -fL --progress-bar -o "$tarball" "$WINE_URL"
	local sum
	sum="$(shasum -a 256 "$tarball" | cut -d' ' -f1)"
	[ "$sum" = "$WINE_SHA256" ] || die "Wine download checksum mismatch ($sum)"
	tar -xf "$tarball" -C "$BASE/wine"
	rm -f "$tarball"
	xattr -dr com.apple.quarantine "$BASE/wine" 2>/dev/null || true
	[ -x "$WINE" ] || die "Wine was not where expected: $WINE"
}

# Pick the image for disc N from --cdN or from a name like "...CD2of3.b6i".
find_disc() {
	local n="$1" given="$2" found
	if [ -n "$given" ]; then
		[ -f "$given" ] || die "no such disc image: $given"
		echo "$given"
		return
	fi
	found="$(find "$DISCS" -maxdepth 1 -type f \( -iname "*cd${n}*.b6i" -o -iname "*cd${n}*.iso" -o -iname "*cd${n}*.bin" \) | sort | head -n 1)"
	[ -n "$found" ] || die "no image for disc $n in $DISCS (pass --cd$n)"
	echo "$found"
}

# Extract each disc into discs/cdN with the label and serial Wine reports
# for the drive, so the folders behave like the real CDs.
make_virtual_cds() {
	python3 -c '' 2>/dev/null || die "python3 is needed (run: xcode-select --install)"
	local n img
	for n in 1 2 3; do
		if [ -f "$BASE/discs/cd$n/.windows-label" ]; then
			continue
		fi
		img="$(find_disc "$n" "${CD[$n]}")"
		say "Making virtual CD $n from $(basename "$img")"
		rm -rf "$BASE/discs/cd$n.tmp"
		python3 -I "$CDIMAGE" vcd "$img" "$BASE/discs/cd$n.tmp" >/dev/null
		mv "$BASE/discs/cd$n.tmp" "$BASE/discs/cd$n"
		printf '    label %s\n' "$(cat "$BASE/discs/cd$n/.windows-label")"
	done
}

# D: is the drive the game and setup use, and holds disc 1. E: and F: hold
# discs 2 and 3, in case setup looks for them on any CD drive.
map_drive() {
	ln -sfn "$BASE/discs/cd$2" "$WINEPREFIX/dosdevices/$1:"
}

make_prefix() {
	if [ ! -f "$WINEPREFIX/system.reg" ]; then
		say "Creating the Wine prefix"
		"$WINE" wineboot -i
		"$WINESERVER" -w
		"$WINE" winecfg -v winxp
	fi
	local letter
	for letter in d e f; do
		"$WINE" reg add 'HKLM\Software\Wine\Drives' /v "$letter:" /d cdrom /f /reg:64 >/dev/null
	done
	"$WINESERVER" -k 2>/dev/null || true
	map_drive d 1
	map_drive e 2
	map_drive f 3
}

# Run a Windows program and wait for it and everything it starts. Keys 1-3
# put that disc in D: for setups that ask for a disc swap.
run_and_wait() {
	"$WINE" "$@" &
	sleep 2
	"$WINESERVER" -w &
	local watcher=$! key
	echo "    (if it asks for another disc, press 1, 2 or 3 here, then OK)"
	while kill -0 "$watcher" 2>/dev/null; do
		if [ ! -t 0 ]; then
			sleep 1
		elif read -r -s -n 1 -t 1 key; then
			case "$key" in
				[123]) map_drive d "$key"; echo "    disc $key is in D:" ;;
			esac
		fi
	done
	wait "$watcher" || true
	map_drive d 1
}

find_game() {
	find "$WINEPREFIX/drive_c" -type f -iname 'LinksMMIII.exe' 2>/dev/null | head -n 1
}

run_setup() {
	if [ -n "$(find_game)" ]; then
		say "Links 2003 is already installed in the prefix"
		return
	fi
	say "Running the Links 2003 setup from disc 1"
	echo "    Choose the full install and keep the default folder. You can skip"
	echo "    DirectX and Windows Media Player: Wine has its own."
	(cd "$BASE/discs/cd1" && run_and_wait 'D:\SETUP.EXE')
	[ -n "$(find "$WINEPREFIX/drive_c" -type f -iname 'links*.exe' 2>/dev/null | head -n 1)" ] \
		|| die "setup did not install the game (run setup again to retry)"
}

run_patch() {
	local exe
	exe="$(find_game)"
	if [ -n "$exe" ] && [ -f "$(dirname "$exe")/LinksLauncher.exe" ]; then
		say "The 1.07 patch is already applied"
		return
	fi
	[ -f "$PATCH" ] || die "no 1.07 patch at $PATCH (pass --patch)"
	say "Applying the 1.07 patch"
	run_and_wait "$PATCH"
	[ -n "$(find_game)" ] || die "the 1.07 patch did not install LinksMMIII.exe"
}

make_app() {
	local exe dir
	exe="$(find_game)"
	dir="$(dirname "$exe")"
	say "Making $APP"
	rm -rf "$APP"
	mkdir -p "$APP/Contents/MacOS"
	cat >"$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Links 2003</string>
	<key>CFBundleIdentifier</key><string>io.github.crspytopgn.openlinks2003.original</string>
	<key>CFBundleExecutable</key><string>links2003</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.07</string>
	<key>LSMinimumSystemVersion</key><string>10.15</string>
</dict>
</plist>
EOF
	cat >"$APP/Contents/MacOS/links2003" <<EOF
#!/bin/bash
# Made by openlinks2003 tools/mac/links2003-mac.sh: runs Links 2003 in Wine.
export WINEPREFIX="$WINEPREFIX"
export WINEDEBUG=-all
ln -sfn "$BASE/discs/cd1" "$WINEPREFIX/dosdevices/d:"
cd "$dir" && exec "$WINE" "\${LINKS2003_EXE:-LinksMMIII.exe}" "\$@"
EOF
	chmod +x "$APP/Contents/MacOS/links2003"
}

cmd_setup() {
	install_wine
	make_virtual_cds
	make_prefix
	run_setup
	run_patch
	make_app
	say "Done. Open \"$APP\" to play (or run: $0 play)."
}

cmd_play() {
	find_wine
	local exe
	exe="$(find_game)"
	[ -n "$exe" ] || die "Links 2003 is not installed yet (run: $0 setup)"
	map_drive d 1
	if [ "${1:-}" = --launcher ]; then
		exe="$(dirname "$exe")/LinksLauncher.exe"
	fi
	cd "$(dirname "$exe")"
	exec "$WINE" "$(basename "$exe")"
}

main() {
	local cmd="${1:-setup}"
	[ $# -gt 0 ] && shift
	DISCS="$DEFAULT_DISCS"
	PATCH=""
	CD=("" "" "" "")
	case "$cmd" in
		setup)
			while [ $# -gt 0 ]; do
				case "$1" in
					--discs) DISCS="$2"; shift 2 ;;
					--cd1) CD[1]="$2"; shift 2 ;;
					--cd2) CD[2]="$2"; shift 2 ;;
					--cd3) CD[3]="$2"; shift 2 ;;
					--patch) PATCH="$2"; shift 2 ;;
					*) die "unknown option $1" ;;
				esac
			done
			[ -n "$PATCH" ] || PATCH="$DISCS/Links2k3_107_Final.exe"
			mkdir -p "$BASE"
			cmd_setup
			;;
		play) cmd_play "$@" ;;
		winecfg) find_wine; exec "$WINE" winecfg ;;
		*) sed -n '2,17p' "$0"; exit 1 ;;
	esac
}

main "$@"
