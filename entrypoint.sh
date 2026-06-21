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
REBUILD_MARKER="${DATA_DIR}/.osrm-graph-ready"
FORCE_OPS_LOCK="${DATA_DIR}/.force-ops-in-progress"

osrm_ready() {
  [ -f "${OSRM_BASE}" ] \
    || [ -f "${OSRM_BASE}.hsgr" ] \
    || [ -f "${OSRM_BASE}.cells" ]
}

pbf_is_valid() {
  local file="$1"
  local size

  [ -f "${file}" ] || return 1
  size="$(wc -c < "${file}" | tr -d ' ')"
  [ "${size}" -gt 1000000 ] || return 1
  osmium fileinfo "${file}" >/dev/null 2>&1
}

invalidate_pbf_if_corrupt() {
  local file="$1"
  if [ -f "${file}" ] && ! pbf_is_valid "${file}"; then
    log "PBF inválido, eliminando: ${file} ($(wc -c < "${file}" | tr -d ' ') bytes)"
    rm -f "${file}" "${file}.part"
    return 0
  fi
  return 1
}

purge_pbf_cache() {
  log "Limpiando caché PBF en ${DATA_DIR}..."
  rm -f \
    "${PBF_FILE}" \
    "${DATA_DIR}/salta.osm.pbf" \
    "${DATA_DIR}/salta-capital.osm.pbf" \
    "${DATA_DIR}/argentina.osm.pbf" \
    "${DATA_DIR}/argentina-latest.osm.pbf" \
    "${DATA_DIR}/argentina-260618.osm.pbf" \
    "${DATA_DIR}"/*.osm.pbf.part
}

download_pbf_url() {
  local dest="$1"
  local url="$2"
  log "Descargando PBF desde ${url}..."
  curl -fsSL -A "${USER_AGENT}" --connect-timeout 60 --max-time 7200 -C - -o "${dest}.part" "${url}"
  mv -f "${dest}.part" "${dest}"
  if ! pbf_is_valid "${dest}"; then
    log "ERROR: descarga inválida desde ${url}"
    rm -f "${dest}" "${dest}.part"
    return 1
  fi
}

download_argentina_pbf() {
  local dest="${DATA_DIR}/argentina-latest.osm.pbf"

  invalidate_pbf_if_corrupt "${dest}" || true

  if [ -f "${dest}" ] && pbf_is_valid "${dest}"; then
    echo "${dest}"
    return 0
  fi

  log "Descargando Argentina (~400 MB) desde ${PBF_SOURCE_URL}..."
  if [ -f "${dest}.part" ]; then
    log "Reanudando descarga parcial (${dest}.part)..."
  fi
  curl -fsSL -A "${USER_AGENT}" --connect-timeout 60 --max-time 7200 -C - -o "${dest}.part" "${PBF_SOURCE_URL}"
  mv -f "${dest}.part" "${dest}"

  if ! pbf_is_valid "${dest}"; then
    log "ERROR: Argentina PBF inválido tras descarga"
    rm -f "${dest}" "${dest}.part"
    return 1
  fi

  echo "${dest}"
}

resolve_argentina_pbf() {
  if [ -n "${PBF_SOURCE_PATH:-}" ] && [ -f "${PBF_SOURCE_PATH}" ]; then
    if pbf_is_valid "${PBF_SOURCE_PATH}"; then
      echo "${PBF_SOURCE_PATH}"
      return 0
    fi
    log "PBF_SOURCE_PATH inválido: ${PBF_SOURCE_PATH}"
    rm -f "${PBF_SOURCE_PATH}"
  fi

  for candidate in \
    "${DATA_DIR}/argentina-260618.osm.pbf" \
    "${DATA_DIR}/argentina-latest.osm.pbf" \
    "${DATA_DIR}/argentina.osm.pbf"; do
    invalidate_pbf_if_corrupt "${candidate}" || true
    if [ -f "${candidate}" ] && pbf_is_valid "${candidate}"; then
      echo "${candidate}"
      return 0
    fi
  done

  download_argentina_pbf
}

apply_force_flags_once() {
  if osrm_ready; then
    rm -f "${FORCE_OPS_LOCK}"
    return
  fi

  local want=false
  [ "${FORCE_REBUILD:-false}" = "true" ] && want=true
  [ "${FORCE_REEXTRACT:-false}" = "true" ] && want=true

  if [ "${want}" = false ]; then
    return
  fi

  if [ -f "${FORCE_OPS_LOCK}" ]; then
    log "FORCE_REBUILD/REEXTRACT: operación ya iniciada; no se borra caché otra vez (evita crash-loop)."
    return
  fi

  if [ "${FORCE_REEXTRACT:-false}" = "true" ]; then
    log "FORCE_REEXTRACT: limpiando PBF (una sola vez hasta que el grafo esté listo)..."
    purge_pbf_cache
  fi

  if [ "${FORCE_REBUILD:-false}" = "true" ]; then
    log "FORCE_REBUILD: eliminando grafo (una sola vez hasta que termine el build)..."
    rm -f "${DATA_DIR}/${MAP_NAME}.osrm"*
    rm -f "${REBUILD_MARKER}"
  fi

  touch "${FORCE_OPS_LOCK}"
  log "Si el deploy falla, el lock evita re-borrar en cada reinicio. Borrá ${FORCE_OPS_LOCK} solo para forzar de nuevo."
}

prepare_pbf() {
  local url="${PBF_URL:-${SALTA_PBF_URL:-}}"

  invalidate_pbf_if_corrupt "${PBF_FILE}" || true

  if [ -f "${PBF_FILE}" ] && pbf_is_valid "${PBF_FILE}"; then
    log "PBF listo en volumen: ${PBF_FILE}"
    return 0
  fi

  if [ -n "${PBF_PATH:-}" ] && [ -f "${PBF_PATH}" ] && pbf_is_valid "${PBF_PATH}"; then
    log "Copiando PBF local: ${PBF_PATH}"
    cp -f "${PBF_PATH}" "${PBF_FILE}"
    return 0
  fi

  if [ -n "${url}" ]; then
    download_pbf_url "${PBF_FILE}" "${url}"
    return 0
  fi

  if [ "${IMPORT_REGION}" = "argentina" ] || [ "${SALTA_EXTRACT:-true}" = "false" ]; then
    local argentina
    argentina="$(resolve_argentina_pbf)"
    log "Usando Argentina completa: ${argentina}"
    cp -f "${argentina}" "${PBF_FILE}"
    return 0
  fi

  local argentina bbox
  argentina="$(resolve_argentina_pbf)"
  bbox="$(region_bbox)"
  log "Extrayendo ${IMPORT_REGION} con osmium (bbox ${bbox}) — requiere ~3 GB RAM pico..."
  osmium extract -b "${bbox}" "${argentina}" -o "${PBF_FILE}" --overwrite

  if ! pbf_is_valid "${PBF_FILE}"; then
    log "ERROR: extract osmium produjo PBF inválido"
    rm -f "${PBF_FILE}"
    return 1
  fi

  if [ "${KEEP_ARGENTINA_PBF:-false}" != "true" ]; then
    rm -f "${argentina}" "${DATA_DIR}/argentina-latest.osm.pbf" "${DATA_DIR}/argentina.osm.pbf"
    log "Argentina PBF eliminado del volumen (KEEP_ARGENTINA_PBF=false)."
  fi
}

build_osrm_graph() {
  log "Procesando grafo OSRM (10–30 min; healthcheck timeout >= 2400 s)..."
  log "extract..."
  if ! osrm-extract -p /opt/car.lua "${PBF_FILE}"; then
    log "ERROR: osrm-extract falló."
    invalidate_pbf_if_corrupt "${PBF_FILE}" || true
    return 1
  fi
  log "partition..."
  osrm-partition "${OSRM_BASE}"
  log "customize..."
  osrm-customize "${OSRM_BASE}"
  osrm_ready
}

# --- Arranque ---
log "=== OSRM arranque (region=${IMPORT_REGION}) ==="
free -h 2>/dev/null || true

if osrm_ready; then
  log "Grafo existente, arranque rápido."
  rm -f "${FORCE_OPS_LOCK}"
else
  apply_force_flags_once

  for f in "${PBF_FILE}" \
    "${DATA_DIR}/argentina-260618.osm.pbf" \
    "${DATA_DIR}/argentina-latest.osm.pbf" \
    "${DATA_DIR}/argentina.osm.pbf"; do
    invalidate_pbf_if_corrupt "${f}" || true
  done

  if ! prepare_pbf; then
    log "ERROR: prepare_pbf falló"
    exit 1
  fi

  if ! pbf_is_valid "${PBF_FILE}"; then
    log "ERROR: no hay PBF válido en ${PBF_FILE}"
    exit 1
  fi

  if ! build_osrm_graph; then
    log "ERROR: build_osrm_graph falló; el lock ${FORCE_OPS_LOCK} evita re-borrar en el próximo reinicio."
    exit 1
  fi

  touch "${REBUILD_MARKER}"
  rm -f "${FORCE_OPS_LOCK}"

  if [ "${KEEP_PBF:-false}" != "true" ]; then
    rm -f "${PBF_FILE}"
    log "PBF eliminado tras grafo listo (KEEP_PBF=false)."
  fi

  if [ "${FORCE_REBUILD:-false}" = "true" ] || [ "${FORCE_REEXTRACT:-false}" = "true" ]; then
    log "Grafo listo. Poné FORCE_REBUILD=false y FORCE_REEXTRACT=false en Railway."
  fi
fi

log "Servidor listo en puerto ${PORT} (threads=${OSRM_THREADS})"
exec osrm-routed --algorithm mld --port "${PORT}" --threads "${OSRM_THREADS}" "${OSRM_BASE}"
