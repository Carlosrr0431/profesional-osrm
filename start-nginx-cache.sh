#!/bin/bash
# Arranca nginx como proxy con caché HTTP delante de un backend local.
set -euo pipefail

SERVICE_NAME="${1:?service name}"
NGINX_PORT="${NGINX_PORT:?NGINX_PORT required}"
BACKEND_PORT="${BACKEND_PORT:?BACKEND_PORT required}"
HEALTH_URL="${HEALTH_URL:?HEALTH_URL required}"
NGINX_MAIN_CONF="${NGINX_MAIN_CONF:-/etc/nginx/nginx.conf}"
NGINX_SITE_TEMPLATE="${NGINX_SITE_TEMPLATE:-/etc/nginx/templates/site.conf.template}"
CACHE_DIR="${CACHE_DIR:-/tmp/nginx-cache}"

mkdir -p "${CACHE_DIR}" /etc/nginx/conf.d
export NGINX_PORT BACKEND_PORT
envsubst '${NGINX_PORT} ${BACKEND_PORT}' < "${NGINX_SITE_TEMPLATE}" > /etc/nginx/conf.d/default.conf

echo "[${SERVICE_NAME}] Esperando backend en ${HEALTH_URL}..."
ready=false
WAIT_ITERATIONS="${WAIT_ITERATIONS:-90}"
for _ in $(seq 1 "${WAIT_ITERATIONS}"); do
  if curl -fsS "${HEALTH_URL}" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done

if [ "${ready}" != true ]; then
  echo "[${SERVICE_NAME}] ERROR: backend no respondió a tiempo"
  exit 1
fi

echo "[${SERVICE_NAME}] Caché HTTP activa (nginx :${NGINX_PORT} → backend :${BACKEND_PORT})"
exec nginx -c "${NGINX_MAIN_CONF}" -g 'daemon off;'
