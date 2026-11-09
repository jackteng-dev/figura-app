#!/usr/bin/env bash
set -euo pipefail
# A caller may use an installed Flutter; private SDK/cache paths never become project dependencies.
exec flutter "$@"
