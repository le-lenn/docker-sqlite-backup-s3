FROM alpine:3.22.2

RUN apk add --no-cache bash curl ca-certificates sqlite aws-cli openssl

COPY sqlite-to-s3.sh /usr/bin/sqlite-to-s3

ENTRYPOINT ["/usr/bin/sqlite-to-s3"]
CMD ["cron"]
