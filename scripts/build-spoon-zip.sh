#!/usr/bin/env bash
# Build Spoons/EmacsAnywhere.spoon.zip, the file SpoonInstall downloads from
# <repo>/raw/main/Spoons/. Run it after changing anything in
# EmacsAnywhere.spoon/ and commit the zip with the change; CI fails when the
# zip and the source disagree.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p Spoons
rm -f Spoons/EmacsAnywhere.spoon.zip
zip -9 -r -X Spoons/EmacsAnywhere.spoon.zip EmacsAnywhere.spoon -x '*.DS_Store'
echo "Built Spoons/EmacsAnywhere.spoon.zip"
