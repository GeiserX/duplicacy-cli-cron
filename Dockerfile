FROM alpine:3.20

# Start service crond and add it to the default runlevel
RUN rc-service crond start && rc-update add crond
# Download duplicacy
RUN wget -O /usr/local/bin/duplicacy https://github.com/gilbertchen/duplicacy/releases/download/v3.2.3/duplicacy_linux_x64_3.2.3 && chmod +x /usr/local/bin/duplicacy

CMD ["crond", "-f", "-l", "2"]
