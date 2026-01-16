# Spoons build configuration
ZIPDIR := "Spoons"

# Default recipe: build all spoons
default: build

# Build all spoon zip files
build: (build-spoon "EmacsAnywhere")

# Build a specific spoon zip file
build-spoon spoon: (_ensure-zipdir)
    #!/usr/bin/env bash
    set -euo pipefail
    zipfile="{{ZIPDIR}}/{{spoon}}.zip"
    rm -f "$zipfile"
    /usr/bin/zip -9 -r "$zipfile" "{{spoon}}.spoon"
    echo "Built $zipfile"

# Clean all built zip files
clean:
    rm -f {{ZIPDIR}}/*.zip

# Ensure Spoons directory exists
_ensure-zipdir:
    @mkdir -p {{ZIPDIR}}
