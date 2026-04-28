FROM golang:1.26-alpine AS builder
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

FROM alpine:3.23

ARG TARGETARCH

WORKDIR /config

RUN apk update && apk add --no-cache \
    busybox-openrc \
    wget \
    tar

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
