# Pinned to 1.26: Go 1.27's linker cannot build this codebase for arm64.
# It first dies emitting DWARF for highwayhash's arm64 assembly
#   link: error: non-function sym .../highwayhash.zipperMerge t=SRODATA
#         passed to GetFuncDwarfAuxSyms
# and with -ldflags="-s -w" to skip DWARF it panics instead
#   panic: runtime error: index out of range [43315] with length 43315
# amd64 is unaffected either way. 1.26 builds both cleanly (v3.2.5.4).
# CI builds linux/arm64 on pull requests, so a bad bump goes red before merge --
# that is how the re-proposed bump (#26) was caught instead of breaking releases
# for four days the way #23 did.
#
# Do NOT expect this to clear itself. As of 2026-08-31 the bug is unreported:
# no golang/go issue mentions GetFuncDwarfAuxSyms and no Gerrit CL is in flight,
# so nothing upstream is coming. The linker guard is byte-identical in go1.25.0,
# go1.26.0 and go1.27.0, so 1.27 did not get stricter -- its DWARF caller now
# hands that guard a data symbol, which makes this a 1.27 regression. The
# highwayhash assembly is well-formed (GLOBL .zipperMerge(SB), 8, $48).
#
# Also note 1.27-alpine is a floating tag, so once #26 exists Dependabot proposes
# nothing new when a 1.27.x patch lands; #26 only re-tests when a push to main
# rebases it. Before unpinning, build arm64 against the candidate and read the
# result rather than trusting a green tick elsewhere.
FROM golang:1.27-alpine AS builder
# Build duplicacy from source for consistent multi-arch support.
# The official pre-built ARM binary may panic with "unaligned 64-bit atomic
# operation" on 32-bit ARM; building from source with modern Go avoids this.
# See: https://pkg.go.dev/sync/atomic#pkg-note-BUG
RUN apk add --no-cache git
RUN git clone --depth 1 --branch v3.2.5 https://github.com/gilbertchen/duplicacy.git /build
WORKDIR /build
ARG TARGETARCH
ARG TARGETVARIANT
RUN CGO_ENABLED=0 go build -o /duplicacy ./duplicacy

FROM alpine:3.24

ARG TARGETARCH

WORKDIR /config

# tzdata is REQUIRED for the TZ env var to have any effect. Without it musl
# silently falls back to UTC, so crond fires every schedule at UTC o'clock
# regardless of TZ -- backups then run hours away from when they were configured.
RUN apk update && apk add --no-cache \
    busybox-openrc \
    wget \
    tar \
    tzdata

COPY --from=builder /duplicacy /usr/local/bin/duplicacy
RUN chmod +x /usr/local/bin/duplicacy

# Download shoutrrr for the target architecture
RUN case "${TARGETARCH}" in \
      "amd64") SHOUTRRR_ARCH="amd64" ;; \
      "arm64") SHOUTRRR_ARCH="arm64" ;; \
      "arm")   SHOUTRRR_ARCH="armv6" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    wget -O - "https://github.com/containrrr/shoutrrr/releases/download/v0.8.0/shoutrrr_linux_${SHOUTRRR_ARCH}.tar.gz" \
      | tar xz -C /usr/local/bin shoutrrr && \
    chmod +x /usr/local/bin/shoutrrr

RUN mkdir -p /etc/periodic/15min /etc/periodic/hourly /etc/periodic/daily /etc/periodic/weekly /etc/periodic/monthly

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
