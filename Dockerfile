FROM alpine:3.22.2
LABEL author="Lennard"

# Install system dependancies
RUN apk add --no-cache bash curl ca-certificates && rm -rf /var/cache/apk/*

# Install sqlite
RUN apk add --no-cache sqlite && rm -rf /var/cache/apk/*

# Install aws cli via apk to avoid PEP 668 restrictions
RUN apk add --no-cache aws-cli && rm -rf /var/cache/apk/*

COPY sqlite-to-s3.sh /usr/bin/sqlite-to-s3

ENTRYPOINT ["/usr/bin/sqlite-to-s3"]
CMD ["cron"]
