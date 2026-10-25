#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /private/tmp/badge-protocol.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
swiftc -module-cache-path "$test_dir/cache" Sources/Cipher.swift Sources/Wire.swift Tests/main.swift -o "$test_dir/check"
"$test_dir/check" Tests/reference.avi
