FROM ghcr.io/gleam-lang/gleam:v1.12.0-erlang-alpine AS build
COPY . /app/
RUN cd /app && gleam build

FROM oven/bun AS compile
COPY --from=build /app/build/dev/javascript/ /build
WORKDIR /build
RUN bun build --compile --target=bun-linux-x64 /build/condition_overload/entry.mjs --outfile /build/bin/linux-x64/condition_overload
RUN bun build --compile --target=bun-linux-arm64 /build/condition_overload/entry.mjs --outfile /build/bin/linux-arm64/condition_overload
RUN bun build --compile --target=bun-windows-x64 /build/condition_overload/entry.mjs --outfile /build/bin/windows-x64/condition_overload
RUN bun build --compile --target=bun-darwin-x64 /build/condition_overload/entry.mjs --outfile /build/bin/darwin-x64/condition_overload
RUN bun build --compile --target=bun-darwin-arm64 /build/condition_overload/entry.mjs --outfile /build/bin/darwin-arm64/condition_overload
RUN bun build --compile --target=bun-x64-musl /build/condition_overload/entry.mjs --outfile /build/bin/x64-musl/condition_overload
RUN bun build --compile --target=bun-linux-arm64-musl /build/condition_overload/entry.mjs --outfile /build/bin/linux-arm64-musl/condition_overload

FROM scratch
COPY --from=compile /build/bin/ /
