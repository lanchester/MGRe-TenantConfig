FROM ruby:2.7.1-alpine3.11
ENV LANG=C.UTF-8 \
    BUNDLE_PATH=/bundle \
    APP_DIR=/rails \
    IMAGEMAGICK6_URL=http://dl-4.alpinelinux.org/alpine/v3.11/community/x86_64/ \
    IMAGEMAGICK6_PREFIX=imagemagick6 \
    IMAGEMAGICK6_VER=6.9.10.75-r0
WORKDIR $APP_DIR
COPY /Gemfile $APP_DIR
COPY /Gemfile.lock $APP_DIR
ARG BUNDLE_GITHUB__COM
RUN apk update && \
    apk add --no-cache bash git nodejs tzdata libxml2-dev curl curl-dev make gcc libc-dev g++ mariadb-dev file imagemagick && \
    curl -O "${IMAGEMAGICK6_URL}${IMAGEMAGICK6_PREFIX}-{${IMAGEMAGICK6_VER},c++-${IMAGEMAGICK6_VER},dev-${IMAGEMAGICK6_VER},libs-${IMAGEMAGICK6_VER}}.apk" && \
    apk add --no-cache \
    ${IMAGEMAGICK6_PREFIX}-c++-${IMAGEMAGICK6_VER}.apk \
    ${IMAGEMAGICK6_PREFIX}-dev-${IMAGEMAGICK6_VER}.apk \
    ${IMAGEMAGICK6_PREFIX}-libs-${IMAGEMAGICK6_VER}.apk \
    ${IMAGEMAGICK6_PREFIX}-${IMAGEMAGICK6_VER}.apk && \
    bundle config specific_platform x86_64-linux && \
    bundle config --local build.sassc --disable-march-tune-native && \
    bundle install --jobs=4 && \
    rm -rf /usr/local/bundle/cache/* /usr/local/share/.cache/* /var/cache/* /tmp/* && \
    apk del libxml2-dev curl curl-dev make gcc libc-dev g++
