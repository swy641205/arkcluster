#!/usr/bin/env bash

CRON_AUTO_UPDATE="0 */3 * * *"
CRON_AUTO_BACKUP="0 */1 * * *"
UPDATEONSTART=1
BACKUPONSTART=1
BACKUPONSTOP=1
WARNONSTOP=1
USER_ID=1000
GROUP_ID=1000
TZ="UTC"
MAX_BACKUP_SIZE=500
SERVERMAP="Valguero_P"
SESSION_NAME="ARK Cluster TheIsland"
MAX_PLAYERS=20
RCON_ENABLE="True"
QUERY_PORT=15000
GAME_PORT=15002
RCON_PORT=15003
SERVER_PVE="False"
SERVER_PASSWORD=""
ADMIN_PASSWORD="keepmesecret"
SPECTATOR_PASSWORD="keepmesecret"
MODS="731604991"
CLUSTER_ID="myclusterid"
GAME_USERSETTINGS_INI_PATH="/cluster/myclusterid.GameUserSettings.ini"
GAME_INI_PATH="/cluster/myclusterid.Game.ini"
KILL_PROCESS_TIMEOUT=300
KILL_ALL_PROCESSES_TIMEOUT=300


#!/usr/bin/env bash

# shellcheck source=/dev/null
source /etc/container_environment.sh

function log { echo "$(date +%Y-%m-%dT%H:%M:%SZ): $*"; }

log "###########################################################################"
log "# Started  - $(date)"
log "# Server   - ${SESSION_NAME}"
log "# Cluster  - ${CLUSTER_ID}"
log "# User     - ${USER_ID}"
log "# Group    - ${GROUP_ID}"
log "###########################################################################"
[ -p /tmp/FIFO ] && rm /tmp/FIFO
mkfifo /tmp/FIFO

rm -f /workspace/server/.stopping-server
rm -f /workspace/server/.installing-ark
rm -f /workspace/server/.installing-mods

export TERM=linux

function stop {
    touch /workspace/server/.stopping-server
    if [ "${BACKUPONSTOP}" -eq 1 ] && [ "$(ls -A /workspace/server/ShooterGame/Saved/SavedArks)" ]; then
        log "Creating Backup ..."
        arkmanager backup --cluster
    fi
    if [ "${WARNONSTOP}" -eq 1 ]; then
        arkmanager stop --warn
    else
        arkmanager stop
    fi
    rm -f /workspace/server/.stopping-server
    exit
}

# Change the USER_ID if needed
if [ ! "$(id -u steam)" -eq "$USER_ID" ]; then
    log "Changing steam uid to $USER_ID."
    usermod -o -u "$USER_ID" steam
fi
# Change gid if needed
if [ ! "$(id -g steam)" -eq "$GROUP_ID" ]; then
    log "Changing steam gid to $GROUP_ID."
    groupmod -o -g "$GROUP_ID" steam
fi

[ ! -d /workspace/log ] && mkdir /workspace/log
[ ! -d /workspace/backup ] && mkdir /workspace/backup
[ ! -d /workspace/staging ] && mkdir /workspace/staging
[ ! -d /workspace/steam ] && mkdir /workspace/steam
[ ! -d /workspace/.steam ] && mkdir /workspace/.steam

if [ -f "/usr/share/zoneinfo/${TZ}" ]; then
    log "Setting timezone to ${TZ} ..."
    ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
fi

if [ ! -f /etc/cron.d/arkupdate ]; then
    log "Adding update cronjob (${CRON_AUTO_UPDATE}) ..."
    echo "$CRON_AUTO_UPDATE steam bash -l -c 'arkmanager update --dots --update-mods --warn --ifempty --saveworld --backup >> /workspace/log/ark-update.log 2>&1'" > /etc/cron.d/arkupdate
fi

if [ ! -f /etc/cron.d/arkbackup ]; then
    log "Adding backup cronjob (${CRON_AUTO_BACKUP}) ..."
    echo "$CRON_AUTO_BACKUP steam bash -l -c 'arkmanager backup --cluster >> /workspace/log/ark-backup.log 2>&1'" > /etc/cron.d/arkbackup
fi

# We overwrite the default file each time
cp /home/steam/arkmanager-user.cfg /workspace/default/arkmanager.cfg

# Copy default arkmanager.cfg if it doesn't exist
[ ! -f /workspace/arkmanager.cfg ] && cp /home/steam/arkmanager-user.cfg /workspace/arkmanager.cfg
if [ ! -L /etc/arkmanager/instances/main.cfg ]; then
    rm /etc/arkmanager/instances/main.cfg
    ln -s /workspace/arkmanager.cfg /etc/arkmanager/instances/main.cfg
fi

# Put steam owner of directories (if the uid changed, then it's needed)
chown -R steam:steam /workspace /home/steam /cluster
log "###########################################################################"

if [ ! -d /workspace/server ] || [ ! -f /workspace/server/version.txt ]; then
    log "No game files found. Installing..."
    mkdir -p /workspace/server/ShooterGame/Saved/SavedArks
    mkdir -p /workspace/server/ShooterGame/Content/Mods
    mkdir -p /workspace/server/ShooterGame/Binaries/Linux
    touch /workspace/server/ShooterGame/Binaries/Linux/ShooterGameServer
    chown -R steam:steam /workspace/server
    touch /workspace/server/.installing-ark
    arkmanager install --dots
    rm -f /workspace/server/.installing-ark
else
    if [ "${BACKUPONSTART}" -eq 1 ] && [ "$(ls -A /workspace/server/ShooterGame/Saved/SavedArks/)" ]; then
        log "Creating Backup ..."
        arkmanager backup --cluster
    fi
fi

log "###########################################################################"
log "Installing Mods ..."
if ! arkmanager checkmodupdate --revstatus; then
    touch /workspace/server/.installing-mods
    arkmanager installmods --dots
    rm -f /workspace/server/.installing-mods
fi

log "###########################################################################"
log "Launching ark server ..."
if [ "${UPDATEONSTART}" -eq 1 ]; then
    arkmanager start
else
    arkmanager start -noautoupdate
fi

# Stop server in case of signal INT or TERM
log "###########################################################################"
log "Running ... (waiting for INT/TERM signal)"
trap stop INT
trap stop TERM

read -r < /tmp/FIFO &
wait