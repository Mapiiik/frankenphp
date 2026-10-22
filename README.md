# FrankenPHP

The base of our PHP applications in Docker, so the same Caddy configuration is not copied into every
repository. The image is the official `dunglas/frankenphp` (Alpine) with:

- FrankenPHP rebuilt with the modules of the official build and the rate limit module,
- PHP in production settings, without its version in the headers, UTC unless the application sets
  its own zone, with opcache,
- a non-root user `application` that may bind to ports 80 and 443 and write the data of Caddy,
- the Caddy configuration of [ghcr.io/mapiiik/caddy](https://github.com/Mapiiik/caddy): the PROXY
  protocol always on, `LISTENER_MODE`, `ACCESS` and `RATE_LIMIT`, around `php_server` instead of a
  reverse proxy.

The application brings its PHP extensions, its limits, its code and `app.caddy`.

## An application on it

```dockerfile
FROM ghcr.io/mapiiik/frankenphp:php8.4

RUN install-php-extensions intl pdo_pgsql
RUN echo "memory_limit = 512M" > $PHP_INI_DIR/conf.d/99-memory.ini

COPY docker/caddy/app.caddy /etc/frankenphp/app.caddy
COPY --chown=application:application . /app
ENV SERVER_ROOT=public/

USER application
```

`app.caddy` holds what belongs to the application as three snippets, all of them required, empty if
there is nothing to say:

```caddyfile
# Inside the global frankenphp block
(app_frankenphp) {
	num_threads {$PHP_NUM_THREADS:32}
}

# Inside the site
(app_site) {
	header ?X-Frame-Options "SAMEORIGIN"
}

# Inside php_server
(app_php_server) {
}
```

Start it with the Caddyfile of this image: `CMD ["--config", "/etc/frankenphp/Caddyfile", "--adapter",
"caddyfile"]` (the official image runs `frankenphp run` with it).

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `SERVER_NAME` | `localhost` | The hostname the certificate is issued for, or an IP address in the internal mode. |
| `SERVER_ROOT` | `public/` | The document root, set by the application's image. |
| `LISTENER_MODE` | `direct` | `direct`, `behind-proxy` or `internal`. |
| `PROXY_ALLOW` | `127.0.0.1/32 ::1/128` | Addresses the PROXY protocol header is trusted from. Behind a proxy, its network. |
| `ACCESS` | `public` | `public`, `admin-paths` (`ADMIN_PATHS` only from `ADMIN_IPS`) or `admins-only`. |
| `ADMIN_IPS` | | Addresses or CIDR ranges of administrators, separated by spaces. |
| `ADMIN_PATHS` | | Paths only administrators may open, such as `/admin*`. |
| `RATE_LIMIT` | `off` | `on` limits POST to `RATE_LIMIT_PATHS` per client address. |
| `RATE_LIMIT_PATHS` | | Paths whose POST requests are limited, such as `/login /users/login`. |
| `RATE_LIMIT_EVENTS` | `10` | How many such requests one client address may make in the window. |
| `RATE_LIMIT_WINDOW` | `1m` | The window, such as `30s` or `5m`. |
| `CADDY_GLOBAL_OPTIONS` | | More global options, such as `email admin@example.com`. |
| `FRANKENPHP_CONFIG` | | More options of the global `frankenphp` block. |
| `CADDY_SERVER_EXTRA_DIRECTIVES` | | More directives for the site, before `php_server`. |
| `CADDY_EXTRA_CONFIG` | | More site blocks. |

The modes, access and the rate limit work as in [ghcr.io/mapiiik/caddy](https://github.com/Mapiiik/caddy),
see its README. The rate limit is a second layer: an application with a login limits attempts itself.
Off, the module is in the binary but not on the request path, so it costs nothing.

Keep `/data/caddy` (certificates and the keys of the internal CA) in a volume.

## Tags and updates

For each PHP version: `php8.4` follows FrankenPHP, `1.13-php8.4` its minor and `1.13.2-php8.4` its
patch release, `sha-…-php8.4` the commit and `build-…` what the image was built from. PHP 8.3 the same
with `php8.3`. A nightly build at 2:00 UTC makes a new image only when FrankenPHP, PHP, Alpine or the
builder images changed, an hour before the applications look for a new base.

Check the configuration in every mode with:

```sh
docker run --rm -v "$PWD/tests:/tests:ro" ghcr.io/mapiiik/frankenphp:php8.4 sh /tests/validate.sh
```
