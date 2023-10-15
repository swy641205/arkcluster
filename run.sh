#!/usr/bin/env bash

# shellcheck source=/dev/null
source /etc/container_environment.sh
source /workspace/env.txt

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


# 自動刪除不再MOD變量裡的id

# 將MODS字符串轉換為陣列
IFS=',' read -ra MODS_ARRAY <<< "$MODS"

# 遍歷/server/ShooterGame/Content/Mods目錄下的所有.mod檔案
for mod_file in /workspace/server/ShooterGame/Content/Mods/*.mod; do
    # 如果沒有匹配到任何文件，則跳過迴圈
    [[ ! -e "$mod_file" ]] && continue

    # 獲取檔案名（不包括路徑和副檔名）
    mod_id=$(basename -- "$mod_file" .mod)
    
    # 檢查mod_id是否在MODS_ARRAY中
    if [[ -n "$mod_id" && "$mod_id" != "111111111" && ! " ${MODS_ARRAY[@]} " =~ " ${mod_id} " ]]; then
        log "移除模組 ${mod_id}"
        arkmanager uninstallmod "$mod_id"
    fi

done


log "###########################################################################"
log "Installing Mods ..."
if ! arkmanager checkmodupdate --revstatus; then
    touch /workspace/server/.installing-mods
    arkmanager installmods --dots
    rm -f /workspace/server/.installing-mods
fi



function just_stop {
    arkmanager stop
}

function command {
    while true; do
        read -p "輸入help取得指令說明: " -a userInputArray
        command="${userInputArray[0]}"
        if [ "$command" == "stop" ]; then
            stop
            break
        elif [ "$command" == "reinstall" ]; then
            arkmanager install
        elif [ "$command" == "list-mod" ]; then
            arkmanager list-mods
        elif [ "$command" == "fix-mode" ]; then
            arkmanager stop --warnreason
        elif [ "$command" == "debug" ]; then
            arkmanager run
        elif [ "$command" == "uninstallmod" ]; then
            modId="${userInputArray[1]}"  # 模組ID應該是第二個詞
            arkmanager uninstallmod "$modId"
        elif [ "$command" == "arkmanager" ]; then
            arkmanager "${userInputArray[@]:1}"
        elif [ "$command" == "help" ]; then
            cat <<- EOM
指令說明：
    debug   以偵錯模式開啟伺服器（詳細訊息會顯示在終端機）
    list-mod   列出已安裝的模組
    uninstallmod <id>   移除模組 e.g. uninstallmod 1734595558
    reinstall   重新安裝ark伺服器（若伺服器檔案損毀才使用，比如：缺少材質檔案…）

詳細指令請參考文檔 - 偵錯模式：
    https://ouob.net/ark
EOM
        else
            log "未知指令，請參考文檔：https://ouob.net/ark"
        fi
    done
}


log "###########################################################################"
log "Launching ark server ..."

if [ "$DEBUG" == "True" ]; then
    trap just_stop INT
    trap just_stop TERM
    arkmanager run
elif [ "${UPDATEONSTART}" -eq 1 ]; then
    arkmanager start
    trap stop INT
    trap stop TERM
    service cron start
else
    arkmanager start -noautoupdate
fi


# Stop server in case of signal INT or TERM
log "###########################################################################"
log "Running ... (waiting for INT/TERM signal)"

if [ "$DEBUG" == "False" ]; then
    trap stop INT
    trap stop TERM
    service cron start
fi

command