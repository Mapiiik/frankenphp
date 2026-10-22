#!/bin/sh
# Validates the configuration in every mode, access and rate limit setting, inside the image:
#   docker run --rm -v "$PWD/tests:/tests:ro" <image> sh /tests/validate.sh
set -u
failed=0
check() {
	if out=$(env "$@" frankenphp validate --config /etc/frankenphp/Caddyfile --adapter caddyfile 2>&1); then
		echo "ok    $*"
	else
		echo "FAIL  $*"
		echo "$out" | grep -E '"level":"error"|Error' | tail -2
		failed=1
	fi
}
base="SERVER_NAME=app.example.com"
admins="ADMIN_IPS=192.0.2.10 198.51.100.0/24 2001:db8::/32"
for mode in direct behind-proxy internal; do
	check $base LISTENER_MODE=$mode
	check $base LISTENER_MODE=$mode ACCESS=admin-paths "ADMIN_PATHS=/admin* /if/admin*" "$admins"
	check $base LISTENER_MODE=$mode ACCESS=admins-only "$admins"
	check $base LISTENER_MODE=$mode RATE_LIMIT=on "RATE_LIMIT_PATHS=/login /users/login"
done
check $base LISTENER_MODE=behind-proxy "PROXY_ALLOW=192.168.2.0/24 fd5c:a2e:41b7:1::/64" \
	ACCESS=admins-only "$admins" RATE_LIMIT=on RATE_LIMIT_PATHS=/login RATE_LIMIT_EVENTS=5 RATE_LIMIT_WINDOW=30s \
	"CADDY_GLOBAL_OPTIONS=email admin@example.com" "CADDY_SERVER_EXTRA_DIRECTIVES=header X-Robots-Tag none" \
	"FRANKENPHP_CONFIG=num_threads 4"
exit $failed
