#!/bin/bash
mkdir -p .build && swiftc -O Sources/Snowfall/*.swift -o .build/Snowfall
