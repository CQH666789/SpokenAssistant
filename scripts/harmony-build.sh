#!/usr/bin/env bash
set -euo pipefail

DEVECO_HOME="${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-${DEVECO_HOME}/sdk}"

export PATH="${DEVECO_HOME}/tools/node/bin:${DEVECO_HOME}/tools/ohpm/bin:${DEVECO_HOME}/tools/hvigor/bin:${PATH}"

if [ "$#" -eq 0 ]; then
  set -- assembleApp
fi

hvigorw "$@" --no-daemon
