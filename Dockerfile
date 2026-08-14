# syntax=docker/dockerfile:1

# bump: xevd /XEVD_VERSION=([\d.]+)/ https://github.com/mpeg5/xevd.git|*
# bump: xevd after ./hashupdate Dockerfile XEVD $LATEST
# bump: xevd link "CHANGELOG" https://github.com/mpeg5/xevd/releases/tag/v$LATEST
ARG XEVD_VERSION=0.7.0
ARG XEVD_URL="https://github.com/mpeg5/xevd/archive/refs/tags/v$XEVD_VERSION.tar.gz"
ARG XEVD_SHA256=febfdb532819bbf36b1b04e74d3ef328ad0f0f2db6224ddb7640fce6bd0014f4

# Must be specified
ARG ALPINE_VERSION

FROM alpine:${ALPINE_VERSION} AS base

FROM base AS download
ARG XEVD_URL
ARG XEVD_SHA256
ARG WGET_OPTS="--retry-on-host-error --retry-on-http-error=429,500,502,503 -nv"
WORKDIR /tmp
RUN \
  apk add --no-cache --virtual download \
    coreutils wget tar && \
  wget $WGET_OPTS -O xevd.tar.gz "$XEVD_URL" && \
  echo "$XEVD_SHA256  xevd.tar.gz" | sha256sum --status -c - && \
  mkdir xevd && \
  tar xf xevd.tar.gz -C xevd --strip-components=1 && \
  rm xevd.tar.gz && \
  apk del download

FROM base AS build
COPY --from=download /tmp/xevd/ /tmp/xevd/
ARG TARGETPLATFORM
ARG XEVD_VERSION
WORKDIR /tmp/xevd
RUN \
  case ${TARGETPLATFORM} in \
    linux/arm/v*) \
      mkdir -p /usr/local/lib/pkgconfig /usr/local/include /usr/local/lib/xevd && \
      touch /usr/local/lib/pkgconfig/xevd.pc && \
      touch /usr/local/lib/libxevd.a && \
      touch /usr/local/include/xevd.h && \
      exit 0 \
    ;; \
  esac && \
  apk add --no-cache --virtual build \
    build-base cmake pkgconf && \
  echo v$XEVD_VERSION > version.txt && \
  sed -i 's/mc_filter_bilin/xevdm_mc_filter_bilin/' src_main/sse/xevdm_mc_sse.c && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DARM="$(if [ $(uname -m) = aarch64 ]; then echo TRUE; else echo FALSE; fi)" \
    -DCMAKE_BUILD_TYPE=Release \
    .. && \
  make -j$(nproc) install && \
  ln -sf /usr/local/lib/xevd/libxevd.a /usr/local/lib/libxevd.a && \
  pkg-config --exists --modversion --path xevd && \
  ar -t /usr/local/lib/libxevd.a && \
  readelf -h /usr/local/lib/libxevd.a && \
  apk del build

FROM scratch
ARG XEVD_VERSION
COPY --from=build /usr/local/lib/pkgconfig/xevd.pc /usr/local/lib/pkgconfig/xevd.pc
COPY --from=build /usr/local/lib/libxevd.a /usr/local/lib/libxevd.a
COPY --from=build /usr/local/include/ /usr/local/include/
