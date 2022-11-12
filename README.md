# Mastodon with Docker

This is a setup for Running [Mastodon](https://joinmastodon.org/) with [Docker](https://docker.com/) with all features including email, full-text search, and file support

All behind a [Traefik](https://traefik.io) reverse proxy, in a seperate compose file in-case of wanting more than just Mastodon behind it

## TODO: Expand This README

## Getting Started

```console
$ docker network create external
```

Start the background services
```console
$ docker compose -f mastodon.compose up db redis es minio -d 
$ docker compose -f proxy.compose up -d 
```

Create the Minio bucket and keys
1. Navigate to minio.localhost
2. Login with the username `admin` and password `password` as specified in the `.env` file
3. Create a new bucket with the name `mastodon`
4. Create a new access and secret key
5. Save the keys

Create `mastodon` user in the database
```console
$ docker exec -it mastodon_db psql -U postgres
> CREATE USER mastodon WITH PASSWORD 'password' CREATEDB;
> exit 
```

Then run the Mastodon setup
```console
$ docker run -it -e RAILS_ENV=production -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 -v system:/mastodon/public/system --network mastodon_internal --env-file .env tootsuite/mastodon:v3.5.3 bundle exec rake mastodon:setup
```

After you answer yes to `Save configuratoin` you should save the output to your .env file
and add the following keys to the in the new `.env`
```env
MINIO_ROOT_USER=<your username>
MINIO_ROOT_PASSWORD=<your password>
MINIO_VOLUMES=/data
```

It will error on connecting to redis after creating the user, however it **WILL** create the user, so save the outputted password

[1]: Enter values for what you need

Now you can start the Mastodon services
```console
$ docker compose -f mastodon.compose up -d
```

Confirm that Traefik is properly detecting all of your services by visitig the dashboard ``