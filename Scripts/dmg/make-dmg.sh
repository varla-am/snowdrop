#!/bin/zsh
# Builds the styled Snowdrop DMG (night sky, sakura, vinyl; app on top, Applications below).
# Usage: Scripts/dmg/make-dmg.sh path/to/Snowdrop.app out.dmg
# Needs dmgbuild (writes the Finder layout directly; create-dmg's Finder script loses the background):
#   python3 -m venv ~/Library/Caches/snowdrop-dmgbuild && ~/Library/Caches/snowdrop-dmgbuild/bin/pip install dmgbuild
set -euo pipefail
here=${0:A:h}
app=${1:A}; out=${2:A}
venv=~/Library/Caches/snowdrop-dmgbuild
[[ -x $venv/bin/dmgbuild ]] || { python3 -m venv $venv && $venv/bin/pip -q install dmgbuild; }
cd $here/../..
$venv/bin/dmgbuild -s $here/dmg-settings.py -D app=$app -D settings_dir=$here/dmg-settings.py Snowdrop $out
