#!/bin/bash

set -e

# Build as a distribution package would: tools, shared library, headers,
# man pages and the libinotifytools API documentation.
# Rust binaries carry no RPATH, so no rpath workarounds are needed.
if [ -n "$1" ]; then
  j="$1"
else
  j="-j16"
fi

make $j
make doc
