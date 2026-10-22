#!/bin/bash
# Explicit build preparation; no global install or dependency lifecycle hooks.
set -euo pipefail
cd "$(dirname "$0")/../tools/web-language-services"
if ! command -v node >/dev/null || ! command -v npm >/dev/null; then
    echo "Node.js >=22.22.2 and npm are required to prepare the Web language runtime." >&2
    exit 1
fi
npm ci --ignore-scripts --no-audit --no-fund --maxsockets=2 --registry=https://registry.npmjs.org
node ../../scripts/web_tools.mjs
