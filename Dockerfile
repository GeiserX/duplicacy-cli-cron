FROM alpine:3.23

ARG TARGETARCH
ARG TARGETVARIANT

WORKDIR /config

RUN apk update && apk add --no-cache \
    busybox-openrc \
    wget \
    tar

# Download duplicacy for the target architecture
RUN case "${TARGETARCH}" in \
      "amd64") DUPLICACY_ARCH="x64" ;; \
      "arm64") DUPLICACY_ARCH="arm64" ;; \
      "arm")   DUPLICACY_ARCH="arm" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    wget -O /usr/local/bin/duplicacy \
      "https://github.com/gilbertchen/duplicacy/releases/download/v3.2.5/duplicacy_linux_${DUPLICACY_ARCH}_3.2.5" && \
    chmod +x /usr/local/bin/duplicacy

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