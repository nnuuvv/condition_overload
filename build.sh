#!/usr/bin/env bash

rm ./build/bin -rf

gleam build

bun build --compile --target=bun-linux-x64 ./build/dev/javascript/condition_overload/gleam.main.mjs --outfile ./build/bin/condition_overload

bun build --compile --target=bun-windows-x64 ./build/dev/javascript/condition_overload/gleam.main.mjs --outfile ./build/bin/condition_overload
