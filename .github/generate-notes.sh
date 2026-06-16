#!/bin/bash

set -euo pipefail

readonly new_version=$1

cat <<EOF
### MODULE.bazel Snippet

\`\`\`bzl
bazel_dep(name = "hermetic_android_toolchains", version = "$new_version")
\`\`\`
EOF
