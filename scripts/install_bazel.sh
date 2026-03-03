#!/bin/bash
set -euo pipefail

VERSION="8.5.0"
URL="https://github.com/bazelbuild/bazel/releases/download/${VERSION}/bazel-${VERSION}-installer-linux-x86_64.sh"

echo "=== Installing Bazel ${VERSION} ==="
wget -q "${URL}" -O /tmp/bazel-installer.sh
chmod +x /tmp/bazel-installer.sh
/tmp/bazel-installer.sh --user
rm /tmp/bazel-installer.sh

export PATH="$HOME/bin:$PATH"
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc

bazel --version
echo "=== Bazel installed ==="