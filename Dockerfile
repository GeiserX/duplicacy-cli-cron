# Start with the Alpine base image
FROM alpine:latest

WORKDIR /config

# Install necessary packages
RUN apk update && apk add --no-cache \
    busybox-openrc \
    wget 

# Download duplicacy
RUN wget -O /usr/local/bin/duplicacy https://github.com/gilbertchen/duplicacy/releases/download/v3.2.3/duplicacy_linux_x64_3.2.3 && chmod +x /usr/local/bin/duplicacy

CMD sh -c 'crond -f && trap "exit" TERM; while true; do sleep 1; done'
