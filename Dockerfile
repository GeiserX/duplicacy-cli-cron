FROM alpine:3.21

WORKDIR /config

# Install necessary packages
RUN apk update && apk add --no-cache \
    busybox-openrc \
    wget \
    tar

# Download duplicacy
RUN wget -O /usr/local/bin/duplicacy https://github.com/gilbertchen/duplicacy/releases/download/v3.2.5/duplicacy_linux_x64_3.2.5 \
    && chmod +x /usr/local/bin/duplicacy

# Download and extract shoutrrr
RUN wget -O - https://github.com/containrrr/shoutrrr/releases/download/v0.8.0/shoutrrr_linux_amd64.tar.gz \
    | tar xz -C /usr/local/bin shoutrrr \
    && chmod +x /usr/local/bin/shoutrrr

# Create all periodic directories to prevent cron errors
RUN mkdir -p /etc/periodic/15min /etc/periodic/hourly /etc/periodic/daily /etc/periodic/weekly /etc/periodic/monthly

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]