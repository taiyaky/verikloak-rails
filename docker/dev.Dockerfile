# docker/dev.Dockerfile
FROM ruby:3.4.5-alpine3.22

# Base packages:
# - Runtime: bash (for CI commands), git (bundler-audit update), openssl (runtime lib), tzdata, libstdc++
# - Build deps: build-base, openssl-dev (for native extensions) — removed after bundle install
RUN apk add --no-cache \
      bash \
      git \
      openssl \
      tzdata \
      libstdc++ \
      yaml \
      pkgconf && \
    apk add --no-cache --virtual .build-deps \
      build-base \
      openssl-dev \
      yaml-dev  

WORKDIR /app

# Leverage docker layer caching for gems
COPY verikloak-rails.gemspec ./
RUN mkdir -p lib/verikloak/rails
COPY lib/verikloak/rails/version.rb lib/verikloak/rails/version.rb
COPY Gemfile Gemfile.lock ./

# Faster, more reliable bundler installs
ARG BUNDLE_FROZEN=1
ENV BUNDLE_JOBS=4 BUNDLE_RETRY=3 BUNDLE_FROZEN=$BUNDLE_FROZEN
RUN bundle install

# App source
COPY . .

# Remove build dependencies to slim the image
RUN apk del .build-deps

# Run as non-root for safety in CI/dev, and match host UID/GID for bind-mount write access
ARG UID=1000
ARG GID=1000
RUN addgroup -S -g $GID app \
    && adduser -S -u $UID -G app app \
    && chown -R app:app /app
USER app
