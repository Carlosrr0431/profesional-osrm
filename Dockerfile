FROM ghcr.io/project-osrm/osrm-backend:latest

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates osmium-tool \
  && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV DATA_DIR=/data
ENV IMPORT_REGION=salta
ENV PORT=5000
ENV SALTA_EXTRACT=true
ENV SALTA_BBOX=-68.75,-26.62,-62.00,-21.78
ENV CAPITAL_BBOX=-65.55,-24.90,-65.30,-24.70
ENV PBF_SOURCE_URL=https://download3.bbbike.org/osm/pbf/region/south-america/argentina.osm.pbf
ENV KEEP_ARGENTINA_PBF=false
ENV OSRM_THREADS=1
ENV KEEP_PBF=false

EXPOSE 5000

ENTRYPOINT ["/entrypoint.sh"]
