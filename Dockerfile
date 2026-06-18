FROM ghcr.io/project-osrm/osrm-backend:latest

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates osmium-tool \
  && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV DATA_DIR=/data
ENV MAP_NAME=salta
ENV PORT=5000
ENV SALTA_EXTRACT=true
ENV SALTA_BBOX=-68.75,-26.62,-62.00,-21.78
ENV PBF_SOURCE_URL=https://download.geofabrik.de/south-america/argentina-latest.osm.pbf

EXPOSE 5000

ENTRYPOINT ["/entrypoint.sh"]
