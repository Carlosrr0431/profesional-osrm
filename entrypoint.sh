#!/bin/bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
IMPORT_REGION="${IMPORT_REGION:-salta}"
PORT="${PORT:-5000}"
PBF_SOURCE_URL="${PBF_SOURCE_URL:-https://download3.bbbike.org/osm/pbf/region/south-america/argentina.osm.pbf}"
SALTA_BBOX="${SALTA_BBOX:--68.75,-26.62,-62.00,-21.78}"
CAPITAL_BBOX="${CAPITAL_BBOX:--65.55,-24.90,-65.30,-24.70}"
USER_AGENT="${USER_AGENT:-ProfesionalApp-OSRM/1.0}"
OSRM_THREADS="${OSRM_THREADS:-1}"

mkdir -p "${DATA_DIR}"

log() {
  echo "[osrm $(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >&2
}

region_map_name() {
  case "${IMPORT_REGION}" in
    capital) echo "salta-capital" ;;
    argentina) echo "argentina" ;;
    *) echo "salta" ;;
  esac
}

region_pbf_file() {
  case "${IMPORT_REGION}" in
    capital) echo "${DATA_DIR}/salta-capital.osm.pbf" ;;
    argentina) echo "${DATA_DIR}/argentina.osm.pbf" ;;
    *) echo "${DATA_DIR}/salta.osm.pbf" ;;
  esac
}

region_bbox() {
  case "${IMPORT_REGION}" in
    capital) echo "${CAPITAL_BBOX}" ;;
    *) echo "${SALTA_BBOX}" ;;
  esac
}

MAP_NAME="${MAP_NAME:-$(region_map_name)}"
PBF_FILE="$(region_pbf_file)"
OSRM_BASE="${DATA_DIR}/${MAP_NAME}.osrm"
REBUILD_MARKER="${DATA_DIR}/.force-rebuild-applied"
REEXTRACT_MARKER="${DATA_DIR}/.force-reextract-applied"

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
    touch "${REEXTRACT_MARKER}"
    return
  fi

  if [ "${IMPORT_REGION}" = "argentina" ] || [ "${SALTA_EXTRACT:-true}" = "false" ]; then
    local argentina
    argentina="$(resolve_argentina_pbf)"
    log "Usando Argentina completa: ${argentina}"
    cp -f "${argentina}" "${PBF_FILE}"
    touch "${REEXTRACT_MARKER}"
    return
  fi

  local argentina bbox
  argentina="$(resolve_argentina_pbf)"
  bbox="$(region_bbox)"
  log "Extrayendo ${IMPORT_REGION} (bbox ${bbox}) desde ${argentina}..."
  osmium extract -b "${bbox}" "${argentina}" -o "${PBF_FILE}" --overwrite
  touch "${REEXTRACT_MARKER}"
  if [ "${KEEP_ARGENTINA_PBF:-false}" != "true" ]; then
    rm -f "${argentina}" "${DATA_DIR}/argentina-latest.osm.pbf" "${DATA_DIR}/argentina.osm.pbf"
    log "PBF de Argentina eliminado del volumen (KEEP_ARGENTINA_PBF=false)."
  fi
}

if [ "${FORCE_REBUILD:-false}" = "true" ]; then
  if [ -f "${REBUILD_MARKER}" ] && osrm_ready; then
    log "FORCE_REBUILD ya aplicado (grafo listo). Desactivá FORCE_REBUILD en Railway."
  else
    log "FORCE_REBUILD: eliminando grafo existente (una sola vez)..."
    rm -f "${DATA_DIR}/${MAP_NAME}.osrm"*
    rm -f "${REBUILD_MARKER}"
    log "Asegurate de healthcheck timeout >= 2400 s mientras reconstruye el grafo."
  fi
fi

if [ "${FORCE_REEXTRACT:-false}" = "true" ]; then
  if [ -f "${REEXTRACT_MARKER}" ] && [ -f "${PBF_FILE}" ]; then
    log "FORCE_REEXTRACT ya aplicado (${PBF_FILE} existe). Desactivá FORCE_REEXTRACT en Railway."
  else
    log "FORCE_REEXTRACT: eliminando PBF en caché (una sola vez)..."
    rm -f "${PBF_FILE}" "${DATA_DIR}/argentina-latest.osm.pbf" "${DATA_DIR}/argentina.osm.pbf"
    rm -f "${REEXTRACT_MARKER}"
  fi
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

  touch "${REBUILD_MARKER}"

  if [ "${KEEP_PBF:-false}" != "true" ]; then
    rm -f "${PBF_FILE}"
    log "PBF eliminado tras construir grafo (KEEP_PBF=false)."
  fi

  if [ "${FORCE_REBUILD:-false}" = "true" ]; then
    log "Grafo reconstruido. Poné FORCE_REBUILD=false en Railway."
  fi
else
  log "Grafo existente en ${DATA_DIR}, omitiendo procesamiento."
  touch "${REBUILD_MARKER}" 2>/dev/null || true
fi

log "Servidor listo en puerto ${PORT} (region=${IMPORT_REGION}, threads=${OSRM_THREADS})"
exec osrm-routed --algorithm mld --port "${PORT}" --threads "${OSRM_THREADS}" "${OSRM_BASE}"
