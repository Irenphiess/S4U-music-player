#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p bin
xcrun clang++ -std=c++17 -fobjc-arc -fblocks -dynamiclib \
  -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 \
  -framework AppKit -framework MediaPlayer -framework AudioToolbox \
  -Wl,-install_name,@rpath/libmedia_keys.dylib \
  media_keys.mm -o bin/libmedia_keys.dylib
codesign --force --sign - bin/libmedia_keys.dylib
