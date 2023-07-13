#!/bin/bash

# This file is the ultimate snapshot + backup + notification script for my homeserver.
#
# It takes care of:
#
#     - Creating snapshots of the correct subvolumes depending on day of the week with btrbk
#     - Mounting the BACKUP drive and creating *backups* to external drive with btrbkp
#     - Updating the system (ARCH)
#     - Updating docker containers
#     - performing maintenance tasks such as btrfs-scrub
#     - Sending a mail with a status report of all the results
#
#
# Vorgehensweise:
#
#     1. Detect day of the week and determine correct schedule.
#     2. Execute operations based on schedule
#     3. send the log via email.
#
#
# The schedule is as follows:
#
#     - Daily:
#         - "Daten" snapshot
#
#     - Weekly (every Sunday):
#         1. Mount Backup drive
#         2. Stop docker containers
#         3. Backup persistent volumes from SSD to HDD "Backup" Subvolume via rsync
#         4. Update docker containers (pull) and prune old containers
#         5. Snapshot of all Subvolumes
#         6. restart docker containers
#         7. Backup/sync snapshots to Backup drive according to btrbk retention policy
#         8. unmount backup drive
#         9. update the system
#
#     - Monthly (every last Sunday of month):
#         1. All of weekly
#         2. btrfs-scrub both NAS drive and Backup drive
#         3. Checking S.M.A.R.T values and detecting suspicious values

DRYRUN=true

# Get this script folder path
SCRIPTDIR="$(dirname "$(readlink -f "$BASH_SOURCE")")"
LOGFILE="${SCRIPTDIR}/logs/$(date +%Y%m%d_%H%M%S).log"
LOCKFILE=/tmp/running-maintenance.lock

MOUNT_BKP_DRIVE="/mnt/BACKUP"
MOUNT_NAS="/mnt/NAS"

DOCKER_USER=  # user to execute docker-compose command
COMPOSE_REPO=
DOCKERDATA=

DOCKERDATA_BKP_DIR="${MOUNT_NAS}/Backups/Michi_zusaetzliche-Backups/00_dockerdata"

BTRBK_CONFIG="$COMPOSE_REPO/NATIVE/btrbk.conf"

if $DRYRUN; then
    RSYNC_CMD="rsync --dry-run"
    BTRBK_CMD="btrbk -c $BTRBK_CONFIG -n"
else
    RSYNC_CMD="rsync"
    BTRBK_CMD="btrbk -c $BTRBK_CONFIG"
fi


log()
{
    echo -e "$1" &>> "$LOGFILE"
}

send_email_with_logs()
{
    log "sending email"
    # mail -s "Server Maintenance Log" mps < $LOGFILE
}


# ----------------------------------------------- System -----------------------------------------------


mount_backup_drive()
{
    if findmnt $MOUNT_BKP_DRIVE > /dev/null
    then
        log "$MOUNT_BKP_DRIVE was already mounted!"
    else
        mount $MOUNT_BKP_DRIVE
    fi
}

reboot_required()
{
    local active_kernel current_kernel
    active_kernel=$(uname -r)
    current_kernel=$(pacman -Q linux | sed 's/linux //')
    if [[ $active_kernel != $current_kernel ]]; then
        log "A reboot is required! \n\trunning: $active_kernel \n\tinstalled: $current_kernel"
    fi
}

update_system()
{
    # update system
    if checkupdates; then
        log "updates available:"
        log "$(checkupdates)"
        pacman -Syu --noconfirm &>> $LOGFILE
    else
        log "No system updates available."
    fi
    reboot_required
}

# ----------------------------------------------- Docker -----------------------------------------------

stop_containers()
{
    # stop all docker containers
    log "stopping containers:"
    log "$(docker ps --format '{{.Names}}')"
    docker stop "$(docker ps -q)"
}

restart_containers()
{
    # restart docker containers
    docker start "$(docker ps -a -q)"
    log "Restarted containers:"
    log "$(docker ps --format '{{.Names}}')"
}

# TODO: not going to work because of environement vars and .env files!
docker_compose_all_services()
{
    log "Running docker-compose $1 on all services..."
    if ! $DRYRUN; then
        sudo -H -E -u $DOCKER_USER bash -c '\
        docker-compose \
            -f $COMPOSE_REPO/dokuwiki/docker-compose.yml \
            -f $COMPOSE_REPO/gitea/docker-compose.yml \
            -f $COMPOSE_REPO/homer/docker-compose.yml \
            -f $COMPOSE_REPO/nextcloud/docker-compose.yml \
            -f $COMPOSE_REPO/traefik/docker-compose.yml \
            -f $COMPOSE_REPO/vaultwarden/docker-compose.yml \
            "$1"' |& tee -a $LOGFILE
    fi
}

docker_prune()
{
    log "Pruning docker system..."
    if ! $DRYRUN; then
        docker system prune -af --volumes &>> $LOGFILE
    fi
}



# ----------------------------------------------- Btrbk & rsync -----------------------------------------------


backup_dockerdata()
{
    log "rsyncing files from dockerdata to Backup subvolumes. If errors occur, they are reported in the next line."
    $RSYNC_CMD -Aaz --delete "${DOCKERDATA}/" "$DOCKERDATA_BKP_DIR" 2>> $LOGFILE
}

snapshot_all()
{
    log "Create snapshots of all subvolumes..."
    # create btrfs snapshots of all subvolumes
    $BTRBK_CMD --preserve snapshot &>> $LOGFILE
}


run_backup()
{
    log "Creating BACKUP: syncing snapshots with external drive using btrbk"
    $BTRBK_CMD resume &>> $LOGFILE
}

scrub() {
    if [[ $# -eq 0 ]]; then
        log "ERROR: no device for scrubbing specified!";
        return 1
    fi
    log "Starting scrub for $1..."
    if ! $DRYRUN; then
        btrfs scrub start -Bd -c 2 -n 4 $1 &>> $LOGFILE
    fi
    btrfs dev stats $1 $>> $LOGFILE
}

# ----------------------------------------------------- Scripts ----------------------------------------------------------


daily()
{
    echo "Running Daily script."
    log "Running Daily script."

    # make a snapshot of "Daten" subvolume
    log "Creating snapshot of 'Daten' subvolume."
    $BTRBK_CMD --preserve snapshot Daten &>> $LOGFILE
}

weekly()
{
    echo "Running Weekly script"
    log "Running Weekly script"

    mount_backup_drive
    stop_containers
    backup_dockerdata
    snapshot_all
    restart_containers
    run_backup

    # unmount backup drive
    sync
    umount $MOUNT_BKP_DRIVE

    update_system
    reboot_required
}

monthly()
{
    echo "Running Monthly script"
    log "Running Monthly script"

    mount_backup_drive
    stop_containers
    backup_dockerdata
    snapshot_all

    # update all containers
    docker_compose_all_services pull
    docker_compose_all_services "up -d"
    docker_prune

    run_backup

    scrub $MOUNT_NAS
    scrub $MOUNT_BKP_DRIVE

    update_system
    reboot_required
}


evaluate_schedule()
{
    ######## determine whether to run daily, weekly or monthly backup operations ########

    # MONTHLY: Last sunday of the month https://unix.stackexchange.com/a/330624
    if [[ $(date -d "$date + 1week" +%d%a) =~ 0[1-7]Sun ]]; then monthly

    # WEEKLY: Every sunday (except last sunday)
    elif [[ $(date +%a) == "Sun" ]]; then weekly

    # DAILY: Every day between 0h and 6h a.m.
    elif [ "$(date +%H)" -ge 0 ] && [ "$(date +%H)" -le 6 ]; then daily

    # other triggers are ignored and a notification is sent to notify the admin of unwanted behavior
    else
        log "Script triggered at the wrong timeframe. It is $(date +%F), $(date +%T)"
        send_email_with_logs
    fi
}


test_ftn()
{
    # mount_backup_drive
    # stop_containers
    # backup_dockerdata
    # restart_containers

    log "this is a test log"
    send_email_with_logs
}

# --------------------------------------------------------- Main -------------------------------------------------------

# check if root
if [[ $(id -u) -ne 0 ]]
then
    echo "Please run as root!"
    exit 1
fi

# create log file with user owner
sudo -u $DOCKER_USER touch "$LOGFILE"

# prevent double-trigger while running:
if [[ -f $LOCKFILE ]]
then
    log "$LOCKFILE exists, so nothing happened!"
    send_email_with_logs
    exit 1
fi

# create lockfile
touch $LOCKFILE
log "DRYRUN: $DRYRUN"


if [[ -z $1 ]];
then
    evaluate_schedule
else
    if [[ "$1" == "--monthly" ]]; then monthly
    elif [[ "$1" == "--daily" ]]; then daily
    elif [[ "$1" == "--weekly" ]]; then weekly
    elif [[ "$1" == "--backup-dockerdata" ]]; then backup_dockerdata
    elif [[ "$1" == "--test" ]]; then test_ftn
    else
        echo "unknown parameter!"
        rm $LOGFILE
        rm $LOCKFILE
        exit 1
    fi
fi

log "$(date +%F), $(date +%T): SUCCESSFULLY FINISHED."
send_email_with_logs
rm $LOCKFILE
exit 0
