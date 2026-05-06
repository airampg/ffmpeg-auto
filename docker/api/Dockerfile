FROM swift:6.0-jammy AS build
WORKDIR /src
COPY Package.swift Package.resolved* ./
COPY Sources ./Sources
COPY Tests ./Tests
RUN swift build -c release --product FFmpegAutoServer --static-swift-stdlib && \
    cp .build/release/FFmpegAutoServer /usr/local/bin/FFmpegAutoServer

FROM ubuntu:24.04 AS runtime
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg zip ca-certificates tzdata libxml2 && \
    rm -rf /var/lib/apt/lists/* && \
    ffmpeg -codecs 2>/dev/null | grep -q libmp3lame && \
    ffmpeg -codecs 2>/dev/null | grep -q libopus && \
    test -x /usr/bin/zip
RUN userdel -r ubuntu 2>/dev/null || true && \
    useradd -r -u 1000 -m -d /workdir -s /usr/sbin/nologin ffauto && \
    mkdir -p /workdir/uploads /workdir/outputs && \
    chown -R ffauto:ffauto /workdir
COPY --from=build /usr/local/bin/FFmpegAutoServer /usr/local/bin/FFmpegAutoServer
USER ffauto
WORKDIR /workdir
EXPOSE 9090
ENV PORT=9090 \
    WORKDIR=/workdir \
    LOG_LEVEL=info
ENTRYPOINT ["/usr/local/bin/FFmpegAutoServer"]
