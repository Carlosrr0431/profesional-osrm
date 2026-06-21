# profesional-osrm

Servidor de rutas **OSRM** para ProfesionalApp (Salta, Argentina).

## Railway — configuración estable

| Setting | Valor |
|---------|-------|
| Volume | `/data` (5 GB) |
| Scale → Memory | **4 GB** (build) / puede bajar a 2 GB cuando el grafo ya existe |
| Scale → CPU | **2 vCPU** |
| Deploy → Healthcheck timeout | **3600 s** (primer build) |
| Deploy → Serverless | Activar cuando esté en verde |

### Variables (arranque normal)

```env
FORCE_REBUILD=false
FORCE_REEXTRACT=false
```

### Reconstruir grafo (una sola vez)

```env
FORCE_REBUILD=true
FORCE_REEXTRACT=true
```

Tras deploy exitoso → volver ambas a `false`.

### Evitar OOM en osmium (recomendado)

No descargues Argentina en cada deploy. Usá **PBF de Salta ya extraído**:

```env
PBF_URL=https://TU_PROYECTO.supabase.co/storage/v1/object/public/osm-data/salta.osm.pbf
```

Generá `salta.osm.pbf` localmente con `infra/geospatial/scripts/prepare-osm-data.ps1` y subilo a Supabase (`upload-pbf-supabase.mjs`).

## Probar

```http
GET https://profesional-osrm-production.up.railway.app/route/v1/driving/-65.42,-24.78;-65.41,-24.79?overview=false
```

## Crash-loop

Si `FORCE_REBUILD`/`FORCE_REEXTRACT` quedan en `true` y el build falla, el entrypoint usa un **lock** en `/data/.force-ops-in-progress` para no borrar el caché en cada reinicio. Borrá ese archivo solo si querés forzar un reset manual.
