# profesional-osrm

Servidor de rutas **OSRM** para ProfesionalApp (Salta, Argentina).  
Despliegue en [Railway](https://railway.app) — **sin pasos locales**.

## Railway (5 minutos)

1. Creá un repo vacío en GitHub: `profesional-osrm`
2. Subí este código (`git push`)
3. En Railway → **New Project** → **Deploy from GitHub** → elegí `profesional-osrm`
4. **Volumes** → montá `/data` (2 GB+)
5. **Networking** → **Generate Domain**
6. **Settings → Deploy → Healthcheck timeout: `2400`** (40 min en el primer arranque o con `FORCE_REBUILD=true`)
7. Esperá el primer deploy (10–30 min). Revisá logs hasta `Servidor listo en puerto`

No hace falta configurar variables: el Dockerfile ya trae los defaults.

## Healthcheck (importante)

Railway solo marca el deploy como **Active** cuando OSRM responde en la ruta de prueba.  
Mientras **construye el grafo**, el servidor aún no escucha → el healthcheck falla si el timeout es corto.

| Situación | Healthcheck timeout |
|-----------|---------------------|
| Grafo ya en `/data` (arranque normal) | 300 s alcanza |
| Primer deploy o `FORCE_REBUILD=true` | **2400 s** (40 min) |

Path (no cambiar):

```http
/route/v1/driving/-65.42,-24.78;-65.41,-24.79?overview=false
```

Tras un rebuild exitoso, poné `FORCE_REBUILD=false` y podés bajar el timeout a 300 s.

## Probar

```http
GET https://TU-URL.up.railway.app/route/v1/driving/-65.42,-24.78;-65.41,-24.79?steps=true
```

## driver-app

```env
EXPO_PUBLIC_OSRM_URL=https://TU-URL.up.railway.app
```

## Requisitos

| Recurso | Valor |
|---------|-------|
| RAM     | 4–8 GB (primer arranque) |
| Volumen | `/data` obligatorio |

## Variables opcionales

| Variable | Default | Descripción |
|----------|---------|-------------|
| `SALTA_BBOX` | `-68.75,-26.62,-62.00,-21.78` | Bbox provincia Salta |
| `SALTA_EXTRACT` | `true` | `false` = Argentina completa |
| `FORCE_REBUILD` | `false` | `true` = borra grafo y reprocessa (usar con timeout 2400 s) |
| `FORCE_REEXTRACT` | `false` | `true` = borra PBF en caché |
| `PBF_SOURCE_URL` | BBBike Argentina | Mirror alternativo al PBF |
