#!/bin/bash
set -e

PTERODACTYL_URL=$1
PTERODACTYL_TOKEN=$2
JELASTIC_ENV=$3
ACME_EMAIL=$4

if [[ "$EUID" -ne 0 ]]; then
    echo -e "\e[31m[FATAL]\e[39m Currently this script requires being ran as root user - please try again as root."
    exit 1
fi

echo -e "\n\nINSTALL LOG FOR WINGS: $(date --rfc-3339=seconds)\n" >> /var/log/wings-install.log

info() {
    echo -e "\e[34m[INFO]\e[39m $1"
    echo "[INFO] $1" >> /var/log/wings-install.log
}

debug() {
    if [[ ! -z "$DEBUG" ]]; then
        echo -e "\e[96m[DEBUG]\e[39m $1"
    fi
    echo "[DEBUG] $1" >> /var/log/wings-install.log
}

warn() {
    echo -e "\e[33m[WARNING]\e[39m $1"
    echo "[WARNING] $1" >> /var/log/wings-install.log
}

fatal() {
    echo -e "\e[31m[FATAL]\e[39m $1"
    echo "[FATAL] $1" >> /var/log/wings-install.log
    exit 1
}

get_timezone_file() {
    if [[ -f "/etc/timezone" ]]; then
        declare -g "$1=/etc/timezone"
    elif [[ -f "/etc/localtime" ]]; then
        declare -g "$1=/etc/localtime"
    else
        fatal "Couldn't find any supported timezone file."
    fi
}

install_docker() {
    # TODO: Should install curl if not present

    debug "Checking if docker is installed..."
    if [[ ! -x "$(command -v docker)" ]]; then
        info "Missing dependency Docker, running its install script..."
        curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    else
        debug "Docker is already installed, skipping installation of it."
    fi

    # TODO: Check kernel version (and if virtualization packages are installed)

    debug "Starting and enabling docker..."
    systemctl start docker > /dev/null 2>&1
    systemctl enable docker > /dev/null 2>&1

    debug "Checking if docker works..."
    docker run --rm hello-world > /dev/null 2>&1
    if [[ "$?" -ne 0 ]]; then
        fatal "Failed verifying docker support of this machine. The command `docker run hello-world` fails, please look into this and re-run the script after it works."
    fi
}

install_acmesh() {
    mkdir -p /etc/letsencrypt/live/$JELASTIC_ENV
    curl https://get.acme.sh | sh -s email=$ACME_EMAIL
}

install_wings(){
  mkdir -p /etc/pterodactyl
  touch /etc/pterodactyl/config.yml
  
  info "Installing Pterodactyl Wings Service..."
  
  curl -L -o /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/download/latest/wings_linux_amd64 > /dev/null 2>&1
  chmod u+x /usr/local/bin/wings > /dev/null 2>&1

  cat <<EOT > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=600

[Install]
WantedBy=multi-user.target
EOT

  systemctl daemon-reload > /dev/null 2>&1
  systemctl enable wings > /dev/null 2>&1

  info "Adding new Node to Pterodactyl Panel..."
  PTERODACTYL_NODE_ID=$(curl "https://"$PTERODACTYL_URL"/api/application/nodes" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'Authorization: Bearer '$PTERODACTYL_TOKEN'' -X POST -d '{"name": "'$JELASTIC_ENV'", "location_id": 1, "fqdn": "'$JELASTIC_ENV'", "scheme": "https", "memory": 8192, "memory_overallocate": 0, "disk": 102400, "disk_overallocate": 0, "upload_size": 100, "daemon_sftp": 2022, "daemon_listen": 8080}' | jq -r '.attributes.id')
  info "Getting Node configuration from Pterodactyl Panel..."
  PTERODACTYL_RESPONSE=$(curl "https://"$PTERODACTYL_URL"/api/application/nodes/"$PTERODACTYL_NODE_ID"/configuration" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'Authorization: Bearer '$PTERODACTYL_TOKEN'' -X GET)
  PTERODACTYL_NODE_UUID=$(echo $PTERODACTYL_RESPONSE | jq -r '.uuid')
  PTERODACTYL_NODE_TOKEN_ID=$(echo $PTERODACTYL_RESPONSE | jq -r '.token_id')
  PTERODACTYL_NODE_TOKEN=$(echo $PTERODACTYL_RESPONSE | jq -r '.token')

  info "Saving Node configuration..."
  cat <<EOT > /etc/pterodactyl/config.yml
debug: false
uuid: $PTERODACTYL_NODE_UUID
token_id: $PTERODACTYL_NODE_TOKEN_ID
token: $PTERODACTYL_NODE_TOKEN
api:
  host: 0.0.0.0
  port: 8080
  ssl:
    enabled: true
    cert: /etc/letsencrypt/live/$JELASTIC_ENV/fullchain.pem
    key: /etc/letsencrypt/live/$JELASTIC_ENV/privkey.pem
  upload_limit: 100
system:
  data: /var/lib/pterodactyl/volumes
  sftp:
    bind_port: 2022
allowed_mounts: []
remote: 'https://$PTERODACTYL_URL'
EOT
  
  debug "Pterodactyl Node setup..."
  debug "Starting Wings..."
  systemctl start wings > /dev/null 2>&1

  /root/.acme.sh/acme.sh --issue --standalone --keypath /etc/letsencrypt/live/$JELASTIC_ENV/privkey.pem --fullchainpath /etc/letsencrypt/live/$JELASTIC_ENV/fullchain.pem -d $JELASTIC_ENV --reloadcmd "systemctl restart wings"
  /root/.acme.sh/acme.sh --upgrade --auto-upgrade

}

main() {
    info "Script loaded, starting the install process..."

    if [[ ! -x "$(command -v curl)" ]]; then
        fatal "Couldn't find curl installed on the system - please install it first and rerun the script."
    fi

    debug "Retrieving timezone file..."
    get_timezone_file "TIMEZONE_FILE"
    debug "Timezone file is located in $TIMEZONE_FILE."

    install_docker
    install_acmesh
    install_wings
    info "Wings is now installed, install script finished. It may take couple of minutes for everything to boot up."
}

main
