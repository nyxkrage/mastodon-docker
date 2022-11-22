#!/bin/bash
set -eu
IFS=$'\n\t'

# Make sure prerequisite programs are installed
if ! command -v whiptail >/dev/null; then
  echo 'command `whiptail` is not installed'
  exit 1
fi
if ! command -v htpasswd >/dev/null; then
  echo 'command `htpasswd` is not installed'
  exit 1
fi
if ! command -v docker >/dev/null; then
  echo 'command `docker` is not installed'
  exit 1
fi
if ! docker compose version >/dev/null; then
  echo 'command `docker compose` is not installed'
  exit 1
fi

echo "Pulling container images used for bootstrapping"
docker pull tootsuite/mastodon:v3.5.3
docker pull minio/mc:RELEASE.2022-11-07T23-47-39Z

# The actual domain for the services
# ${DOMAIN}
DOMAIN="$(whiptail --inputbox "The domain that will be used for all services\n(eg. example.org if you want mastodon to run on social.example.org)" 10 75 "localhost" 3>&1 1>&2 2>&3)"

# The subdomain on which Mastodon will reside
# ${MASTODON_SUBDOMAIN}
MASTODON_SUBDOMAIN="$(whiptail --inputbox "The subdomain you want mastodon to be accessed on\n(eg. social if you want mastodon to run on social.example.org)" 10 75 "social" 3>&1 1>&2 2>&3)"
if [[ -n "$MASTODON_SUBDOMAIN" ]]; then
  MASTODON_SUBDOMAIN="$MASTODON_SUBDOMAIN."
fi

# The subdomain which will be used to access static files/assets (the files in minio buckets)
# ${FILES_SUBDOMAIN}
FILES_SUBDOMAIN="$(whiptail --inputbox "The subdomain you want static files to be accessed on" 10 75 "files" 3>&1 1>&2 2>&3)"
if [[ -n "$FILES_SUBDOMAIN" ]]; then
  FILES_SUBDOMAIN="$FILES_SUBDOMAIN."
fi

# Email to receive Let's Encrypt notifications to
# ${ACME_EMAIL}
ACME_EMAIL="$(whiptail --inputbox "The email you want to receive emails from Let's Encrypt to" 10 75 "admin@$DOMAIN" 3>&1 1>&2 2>&3)"
# Proxy Password
# ${PASS_HASH}
PROXY_PASS="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w32 | head -n 1)"
PASS_HASH="$(echo $(htpasswd -nBb admin $PROXY_PASS) | sed -e s/\\$/\\$\\$/g)"

# The SMTP server, will often be mailgun or postmark
# ${SMTP_SERVER}
SMTP_SERVER="$(whiptail --inputbox "The SMTP server that will be used to send emails with" 10 75 "mail.$DOMAIN" 3>&1 1>&2 2>&3)"

# The username to login to SMTP with, usually the email
# ${SMTP_USERNAME}
SMTP_USERNAME="$(whiptail --inputbox "Username for email account" 10 75 "$ACME_EMAIL" 3>&1 1>&2 2>&3)"

# Password for the SMTP user
# ${SMTP_PASS}
SMTP_PASS="$(whiptail --passwordbox "Password for email account" 10 75 3>&1 1>&2 2>&3)"

# The email that mastodon will use to send (autofill with the $SMTP_USERNAME as that is the sane behaviour)
# ${MASTODON_EMAIL}
MASTODON_EMAIL="$(whiptail --inputbox "The email address that Mastodon will send from\nThis should in almost all cases be the same as your SMTP username"  10 75 "$SMTP_USERNAME" 3>&1 1>&2 2>&3)"

# The name that should be used when mastodon sends emails
# ${EMAIL_NAME}
EMAIL_NAME="$(whiptail --inputbox "The name that the emails should be sent with" 10 75 "Admin" 3>&1 1>&2 2>&3)"

MASTODON_ADMIN_USER="$(whiptail --inputbox "Username of initial admin account" 10 75 "$EMAIL_NAME" 3>&1 1>&2 2>&3)"
MASTODON_ADMIN_EMAIL="$(whiptail --inputbox "Email of initial admin account" 10 75 "$EMAIL_NAME@$DOMAIN" 3>&1 1>&2 2>&3)"

echo "Generating Secrets..."
# Password for `admin` Minio account
# ${MINIO_PASS}
echo "Generating Minio admin panel password..."
MINIO_PASS="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w32 | head -n 1)"

# Password for `mastodon` Postgres user
# ${PSQL_PASS}
echo "Generating Postgres password..."
PSQL_PASS="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w32 | head -n 1)"
PGPASSWORD="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w32 | head -n 1)"

# Minio access key
# ${MINIO_ACCESS}
echo "Generating Minio access key..."
MINIO_ACCESS="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w12 | head -n 1)"
# Minio secret key
# ${MINIO_SECRET}
echo "Generating Minio secret key..."
MINIO_SECRET="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w32 | head -n 1)"

# All three of these will be generated from mastodon
# ${MASTODON_SECRET_KEY}
echo "Generating Mastodon secret key..."
MASTODON_SECRET_KEY="$(docker run --rm tootsuite/mastodon:v3.5.3 bundle exec rake secret 2>/dev/null)"
# ${MASTODON_OTP_SECRET}
echo "Generating Mastodon one-time passwords secret..."
MASTODON_OTP_SECRET="$(docker run --rm tootsuite/mastodon:v3.5.3 bundle exec rake secret 2>/dev/null)"
# ${VAPID_KEYS}
echo "Generating Mastodon vapid keys..."
VAPID_KEYS="$(docker run --rm tootsuite/mastodon:v3.5.3 bundle exec rake mastodon:webpush:generate_vapid_key 2>/dev/null)"

eval "cat <<EOF
$(<templates/.env)
EOF
" > .env
eval "cat <<EOF
$(<templates/proxy.compose)
EOF
" > proxy.compose
eval "cat <<EOF
$(<templates/mastodon.compose)
EOF
" > mastodon.compose

echo 'Creating `external` docker network...'
docker network create external >/dev/null 2>&1 || true

echo "Starting background services needed for bootstrapping..."
docker compose -f mastodon.compose up db redis es minio -d
docker compose -f proxy.compose up -d

echo 'Waiting for `mastodonDb` container to report healthy...'
until [ "$(docker inspect -f {{.State.Health.Status}} mastodonDb)" == "healthy" ]; do
    sleep 1;
done;
echo 'Creating `mastodon` database user...'
docker exec mastodonDb psql -U postgres -c "CREATE USER mastodon WITH PASSWORD '$PSQL_PASS' CREATEDB"
echo "Creating and seeding database..."
docker run --rm --network mastodonInternalNet --env-file .env -e RAILS_ENV=production tootsuite/mastodon:v3.5.3 bundle exec rake db:setup

echo 'Waiting for `mastodonMinio` container to report healthy...'
until [ "$(docker inspect -f {{.State.Health.Status}} mastodonMinio)" == "healthy" ]; do
    sleep 1;
done;
echo "Bootstrapping Minio bucket and access keys..."
docker run --rm --entrypoint '' --network external minio/mc:RELEASE.2022-11-07T23-47-39Z sh -c "mc alias set minio http://mastodonMinio:9000/ admin $MINIO_PASS && mc admin user svcacct add --access-key $MINIO_ACCESS --secret-key $MINIO_SECRET minio mastodon && mc mb minio/mastodon && mc anonymous set download minio/mastodon"

echo "Starting all Mastodon services..."
docker compose -f mastodon.compose up -d

echo 'Waiting for `mastodonWeb` container to report healthy...'
until [ "$(docker inspect -f {{.State.Health.Status}} mastodonWeb)" == "healthy" ]; do
    sleep 1;
done;
echo "Creating Mastodon admin user"
MASTODON_ADMIN_PASS="$(docker exec -e RAILS_ENV=production mastodonWeb bash -c "sed -i.bak -e '/    - \w\+/d' ~/config/settings.yml && tootctl accounts create $MASTODON_ADMIN_USER --email $MASTODON_ADMIN_EMAIL --confirmed --role admin && cp ~/config/settings.yml.bak ~/config/settings.yml" | grep password: | cut -d' ' -f3)"

echo "Credentials:"
echo "Proxy Dashboard: admin:$PROXY_PASS"
echo "Postgres: admin:$PSQL_PASS"
echo "Minio Dashboard: admin:$MINIO_PASS"
echo "Mastodon Admin: $MASTODON_ADMIN_EMAIL:$MASTODON_ADMIN_PASS"

echo "Mastodon is up and running"
echo "You can now visit your Mastodon instance at $MASTODON_SUBDOMAIN.$DOMAIN"
