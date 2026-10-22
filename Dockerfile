# FrankenPHP with our configuration and the rate limit module, see the README
ARG PHP_VERSION=8.4

############################
# FrankenPHP with one module more
############################
# The modules of the official build and the rate limit. The environment and the linker flags are those
# of the official build (go.sh and alpine.Dockerfile in the builder image), the larger thread stack
# above all: the default one of musl is small for deep recursion.
FROM dunglas/frankenphp:builder-php${PHP_VERSION}-alpine AS builder
COPY --from=caddy:2-builder-alpine /usr/bin/xcaddy /usr/bin/xcaddy
RUN FRANKENPHP_VERSION="$(echo "$CGO_CFLAGS" | sed -n 's/.*-DFRANKENPHP_VERSION=\([^ ]*\).*/\1/p')" \
 && CGO_ENABLED=1 \
    XCADDY_SETCAP=1 \
    GOFLAGS="$GOFLAGS -tags=nobadger,nomysql,nopgx,deprecated_topic,deprecated_claim" \
    CGO_CFLAGS="$CGO_CFLAGS $(php-config --includes) $(sh ./mtls-cflags.sh)" \
    CGO_LDFLAGS="$CGO_LDFLAGS $(php-config --ldflags) $(php-config --libs)" \
    XCADDY_GO_BUILD_FLAGS="-ldflags=\"-w -s -extldflags '-Wl,-z,stack-size=0x80000' -X 'github.com/caddyserver/caddy/v2.CustomVersion=FrankenPHP $FRANKENPHP_VERSION PHP $PHP_VERSION Caddy' -X 'github.com/caddyserver/caddy/v2.CustomBinaryName=frankenphp' -X 'github.com/caddyserver/caddy/v2/modules/caddyhttp.ServerHeader=FrankenPHP Caddy'\"" \
    xcaddy build \
        --output /usr/local/bin/frankenphp \
        --with github.com/dunglas/frankenphp=./ \
        --with github.com/dunglas/frankenphp/caddy=./caddy/ \
        --with github.com/dunglas/caddy-cbrotli \
        --with github.com/dunglas/mercure/caddy \
        --with github.com/dunglas/vulcain/caddy \
        --with github.com/mholt/caddy-ratelimit

FROM dunglas/frankenphp:php${PHP_VERSION}-alpine
COPY --from=builder /usr/local/bin/frankenphp /usr/local/bin/frankenphp

############################
# PHP
############################
# What every application of ours had: production settings, no version in the headers, UTC unless the
# application sets its own zone. The extensions and the limits are the application's.
RUN cp $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini \
 && echo "expose_php = Off" > $PHP_INI_DIR/conf.d/90-expose.ini \
 && echo "date.timezone = UTC" > $PHP_INI_DIR/conf.d/90-timezone.ini \
 && install-php-extensions opcache

############################
# Caddy
############################
COPY caddy/ /etc/frankenphp/

############################
# Non-root runtime
############################
# The applications run as this user: it may bind to ports 80 and 443 and write the data of Caddy. The
# image of the application switches to it (USER application) after installing what it needs.
RUN adduser -D application \
 && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
 && chown -R application:application /config/caddy /data/caddy
