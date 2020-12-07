#!/bin/bash
set -e

VERSION=""

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

upgrade_wings(){
  info "Updating Pterodactyl Wings Service..."
  
  curl -L -o /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/download/v1.1.3/wings_linux_amd64 > /dev/null 2>&1
  chmod u+x /usr/local/bin/wings > /dev/null 2>&1

  debug "Starting Wings..."
  systemctl restart wings > /dev/null 2>&1

}

main() {
    info "Script loaded, starting the install process..."

    if [[ ! -x "$(command -v curl)" ]]; then
        fatal "Couldn't find curl installed on the system - please install it first and rerun the script."
    fi

    upgrade_wings
    info "Wings is now updated, install script finished. It may take couple of minutes for everything to boot up."
}

main
