FROM ghcr.io/project-osrm/osrm-backend:latest

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates osmium-tool nginx gettext-base \
  && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY nginx-main.conf /etc/nginx/nginx.conf
COPY nginx-site.conf.template /etc/nginx/templates/site.conf.template
COPY start-nginx-cache.sh /usr/local/bin/start-nginx-cache.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/start-nginx-cache.sh

ENV DATA_DIR=/data
ENV IMPORT_REGION=salta
ENV MAP_NAME=salta
ENV PORT=5000
ENV SALTA_EXTRACT=true
ENV SALTA_BBOX=-68.75,-26.62,-62.00,-21.78
ENV CAPITAL_BBOX=-65.55,-24.90,-65.30,-24.70
ENV PBF_SOURCE_URL=https://download3.bbbike.org/osm/pbf/region/south-america/argentina.osm.pbf
ENV KEEP_ARGENTINA_PBF=false
ENV OSRM_THREADS=1
ENV KEEP_PBF=false
ENV CACHE_ENABLED=true
ENV OSRM_BACKEND_PORT=5001

EXPOSE 5000

ENTRYPOINT ["/entrypoint.sh"]
