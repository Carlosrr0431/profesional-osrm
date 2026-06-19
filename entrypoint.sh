#!/bin/bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
MAP_NAME="${MAP_NAME:-salta}"
PBF_FILE="${DATA_DIR}/${MAP_NAME}.osm.pbf"
OSRM_BASE="${DATA_DIR}/${MAP_NAME}.osrm"
PORT="${PORT:-5000}"
PBF_SOURCE_URL="${PBF_SOURCE_URL:-https://download3.bbbike.org/osm/pbf/region/south-america/argentina.osm.pbf}"
SALTA_BBOX="${SALTA_BBOX:--68.75,-26.62,-62.00,-21.78}"
USER_AGENT="${USER_AGENT:-ProfesionalApp-OSRM/1.0}"

mkdir -p "${DATA_DIR}"

log() {
  echo "[osrm $(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

osrm_ready() {
  [ -f "${OSRM_BASE}" ] \
    || [ -f "${OSRM_BASE}.hsgr" ] \
    || [ -f "${OSRM_BASE}.cells" ]
}

resolve_argentina_pbf() {
  if [ -n "${PBF_SOURCE_PATH:-}" ] && [ -f "${PBF_SOURCE_PATH}" ]; then
    echo "${PBF_SOURCE_PATH}"
    return
  fi

  for candidate in \
    "${DATA_DIR}/argentina-260618.osm.pbf" \
    "${DATA_DIR}/argentina-latest.osm.pbf" \
    "${DATA_DIR}/argentina.osm.pbf"; do
    if [ -f "${candidate}" ]; then
      echo "${candidate}"
      return
    fi
  done

  local dest="${DATA_DIR}/argentina-latest.osm.pbf"
  if [ ! -f "${dest}" ]; then
    log "Descargando Argentina desde ${PBF_SOURCE_URL}..."
    curl -fsSL -A "${USER_AGENT}" --connect-timeout 60 --max-time 7200 -C - -o "${dest}.part" "${PBF_SOURCE_URL}"
    mv -f "${dest}.part" "${dest}"
  fi
  echo "${dest}"
}

prepare_pbf() {
  if [ -f "${PBF_FILE}" ]; then
    log "PBF existente en volumen: ${PBF_FILE}"
    return
  fi

  if [ -n "${PBF_PATH:-}" ] && [ -f "${PBF_PATH}" ]; then
    log "Usando PBF local: ${PBF_PATH}"
    cp -f "${PBF_PATH}" "${PBF_FILE}"
    return
  fi

  if [ -n "${PBF_URL:-}" ]; then
    log "Descargando PBF desde ${PBF_URL}..."
    curl -fsSL -A "${USER_AGENT}" --connect-timeout 60 --max-time 7200 -o "${PBF_FILE}" "${PBF_URL}"
    return
  fi

  if [ "${IMPORT_REGION:-salta}" = "argentina" ] || [ "${SALTA_EXTRACT:-true}" = "false" ]; then
    local argentina
    argentina="$(resolve_argentina_pbf)"
    log "Usando Argentina completa: ${argentina}"
    cp -f "${argentina}" "${PBF_FILE}"
    return
  fi

  local argentina
  argentina="$(resolve_argentina_pbf)"
  log "Extrayendo provincia de Salta (bbox ${SALTA_BBOX}) desde ${argentina}..."
  osmium extract -b "${SALTA_BBOX}" "${argentina}" -o "${PBF_FILE}" --overwrite
  if [ "${KEEP_ARGENTINA_PBF:-true}" != "true" ]; then
    rm -f "${argentina}"
  fi
}

if [ "${FORCE_REBUILD:-false}" = "true" ]; then
  log "FORCE_REBUILD: eliminando grafo existente..."
  rm -f "${DATA_DIR}/${MAP_NAME}.osrm"*
  log "Asegurate de healthcheck timeout >= 2400 s mientras reconstruye el grafo."
fi

if [ "${FORCE_REEXTRACT:-false}" = "true" ]; then
  log "FORCE_REEXTRACT: eliminando PBF en caché..."
  rm -f "${PBF_FILE}" "${DATA_DIR}/argentina-latest.osm.pbf" "${DATA_DIR}/argentina.osm.pbf"
fi

if ! osrm_ready; then
  prepare_pbf

  if [ ! -f "${PBF_FILE}" ]; then
    log "ERROR: no se encontró ${PBF_FILE} después de prepare_pbf"
    exit 1
  fi

  log "Procesando grafo OSRM (puede tardar 10-30 min; el healthcheck debe esperar)..."
  log "extract..."
  osrm-extract -p /opt/car.lua "${PBF_FILE}"
  log "partition..."
  osrm-partition "${OSRM_BASE}"
  log "customize..."
  osrm-customize "${OSRM_BASE}"

  if ! osrm_ready; then
    log "ERROR: el grafo no se generó correctamente en ${DATA_DIR}"
    exit 1
  fi

  if [ "${KEEP_PBF:-false}" != "true" ]; then
    rm -f "${PBF_FILE}"
  fi

  if [ "${FORCE_REBUILD:-false}" = "true" ]; then
    log "Grafo reconstruido. Poné FORCE_REBUILD=false en Railway y redeploy."
  fi
else
  log "Grafo existente en ${DATA_DIR}, omitiendo procesamiento."
fi

log "Servidor listo en puerto ${PORT}"
exec osrm-routed --algorithm mld --port "${PORT}" "${OSRM_BASE}"
