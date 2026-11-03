#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

# Some Command Line Tools builds fail to discover the bundled Testing macros.
# Resolve within the selected Apple toolchain; never download a test dependency.
swift_bin="$(xcrun --find swift)"
testing_plugin="$(dirname "$swift_bin")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
test_args=(test --disable-xctest)
if [[ -f "$testing_plugin" ]]; then
    test_args+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
"$swift_bin" "${test_args[@]}" "$@"
