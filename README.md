# Mastodon with Docker

This is a setup for Running [Mastodon](https://joinmastodon.org/) with [Docker](https://docker.com/) with all features including email, full-text search, and file support

All behind a [Traefik](https://traefik.io) reverse proxy, in a seperate compose file in-case of wanting more than just Mastodon behind it

## Getting Started

1. Make sure to set `vm.max_map_count` to at least `262144` for ElasticSearch to work
```console
# sysctl -w vm.max_map_count=262144
# echo "vm.max_map_count = 262144" > /etc/sysctl.d/96-max-map-count.conf
```

2. Make sure you can execute `docker` without root
3. Make sure `whiptail`, `htpasswd`, `docker` and `docker compose` are available from the command line
4. Run the `setup.sh` script
```console
$ bash setup.sh
```