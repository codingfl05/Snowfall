#!/bin/bash
set -e

./build.sh
pkill -x Snowfall 2>/dev/null || true

if [ -n "$SNOW_DEBUG" ]; then
    .build/Snowfall.app/Contents/MacOS/Snowfall
else
    open .build/Snowfall.app
fi
