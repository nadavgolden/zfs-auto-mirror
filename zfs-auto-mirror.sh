#!/bin/sh

LOG_DEBUG=1
LOG_INFO=2
LOG_WARNING=3
LOG_ERROR=4

LOG_LEVEL=${LOG_WARNING}
FORCE_MIRROR=0

log_debug() {
    if [ ${LOG_LEVEL} -le ${LOG_DEBUG} ] ; then
        echo "\e[32m[DEBUG]\e[39m $*"
    fi
}

log_info() {
    if [ ${LOG_LEVEL} -le ${LOG_INFO} ] ; then
        echo "\e[34m[INFO]\e[39m $*"
    fi
}

log_warning() {
    if [ ${LOG_LEVEL} -le ${LOG_WARNING} ] ; then
        echo >&2 "\e[33m[WARNING]\e[39m $*"
    fi
}

log_error() {
    if [ ${LOG_LEVEL} -le ${LOG_ERROR} ] ; then
        echo >&2 "\e[31m[ERROR]\e[39m $*"
    fi
}

# send_incremental target snap1 snap2 local_dataset
send_incremental() {
    local TARGET=$1
    local SNAP1=$2
    local SNAP2=$3
    local LOCAL_DATASET=$4

    log_debug "Sending incremental backup from ${SNAP1} to ${SNAP2}"

    ssh ${TARGET} "zfs send -c -i ${SNAP1} ${SNAP2} | gzip" | gzip -d | zfs recv -F -v ${LOCAL_DATASET}
    # echo "ssh ${TARGET} zfs send -c -I ${SNAP1} ${SNAP2} | gzip \| gzip -d \| zfs recv -F -v ${LOCAL_DATASET}" && return 0
    # did not work
    return $?
}

# send_full_sync target remote_snapshot local_dataset
send_full_sync() {
    local TARGET=$1
    local REMOTE_SNAP=$2
    local LOCAL_DATASET=$3

    log_debug "Mirroring ${TARGET}:${REMOTE_SNAP} into ${LOCAL_DATASET}"

    ssh ${TARGET} "zfs send -c ${REMOTE_SNAP} | gzip" | gzip -d | zfs recv -F -v ${LOCAL_DATASET}
    return $?
}

# mirror target remote_dataset local_dataset
# target - user@host
# remote_dataset - dataset to mirror from
# local_dataset - mirrored dataset
mirror() {
    local TARGET=$1
    local REMOTE_DATASET=$2
    local LOCAL_DATASET=$3

    # local and remote snapshots are sorted by creation date
    LOCAL_SNAPSHOTS=$(zfs list -t snapshot -H -S creation -o name ${LOCAL_DATASET} | cut -d "@" -f2-)
    REMOTE_SNAPSHOTS=$(ssh ${TARGET} "zfs list -t snapshot -H -S creation -o name ${REMOTE_DATASET}" | cut -d "@" -f2-)
    LAST_LOCAL_SNAPSHOT=$(echo ${LOCAL_SNAPSHOTS} | head -n1 | awk '{print $1;}')
    LAST_REMOTE_SNAPSHOT=$(echo ${REMOTE_SNAPSHOTS} | head -n1 | awk '{print $1;}')

    log_debug "Local snapshots: ${LOCAL_SNAPSHOTS}"
    log_debug "Remote snapshots: ${REMOTE_SNAPSHOTS}"

    # if remote dataset does not exist, there is nothing to do
    if [ -z "$(ssh ${TARGET} "zfs list -H -o name | grep ${REMOTE_DATASET}")" ]; then
        log_error "Remote dataset \"${REMOTE_DATASET}\" does not exist"
        return 1
    fi

    # if remote dataset has no snapshots, there is nothing to backup
    if [ -z "${REMOTE_SNAPSHOTS}" ]; then
        log_error "Remote dataset \"${REMOTE_DATASET}\" has no snapshots"
        return 1
    fi

    # if local dataset does not exist, do a full sync
    if [ -z "$(zfs list -H -o name | grep ${LOCAL_DATASET})" ]; then
        log_error "Local dataset \"${LOCAL_DATASET}\" does not exist, starting full sync"
        send_full_sync ${TARGET} ${REMOTE_DATASET}@${LAST_REMOTE_SNAPSHOT} ${LOCAL_DATASET}
        return $?
    fi

    # if there are no local snpashots we cannot do an incremental
    if [ -z "${LOCAL_SNAPSHOTS}" ]; then
        log_info "No local snapshots, starting full sync"
        send_full_sync ${TARGET} ${REMOTE_DATASET}@${LAST_REMOTE_SNAPSHOT} ${LOCAL_DATASET}
        return $?
    fi

    if [ "${LAST_LOCAL_SNAPSHOT}" = "${LAST_REMOTE_SNAPSHOT}" ]; then
        log_info "Datasets are up-to-date, done"
        return 0
    fi

    # try to find an incremental backup
    for LOCAL_SNAP in ${LOCAL_SNAPSHOTS}; do
        # if the current snapshot does not exist on the remote, we can't do an incremental with it
        if [ -z "$(echo ${REMOTE_SNAPSHOTS} | grep ${LOCAL_SNAP})" ]; then
            log_info "Snapshot ${LOCAL_SNAP} not found in remote, skipping"
            continue
        fi 

        for REMOTE_SNAP in ${REMOTE_SNAPSHOTS}; do
            if [ "${LOCAL_SNAP}" = "${REMOTE_SNAP}" ]; then
                log_info "Comparing the same snapshot (${LOCAL_SNAP}), done"
                return 0
            fi

            log_debug "Current diff: from ${LOCAL_SNAP} to ${REMOTE_SNAP}"
            send_incremental ${TARGET} ${REMOTE_DATASET}@${LOCAL_SNAP} ${REMOTE_DATASET}@${REMOTE_SNAP} ${LOCAL_DATASET} && return 0
        done
    done

    log_error "Failed to find valid incremental sync"

    if [ ${FORCE_MIRROR} -eq 1 ]; then
        log_warning "Forcing full sync"
        zfs destroy -r ${LOCAL_DATASET} || (log_error "Failed to destroy ${LOCAL_DATASET}" && return 1)
        send_full_sync ${TARGET} ${REMOTE_DATASET}@${LAST_REMOTE_SNAPSHOT} ${LOCAL_DATASET} || (log_error "Failed to forcibly sync" && return 1)
    fi

}

print_usage() {
    echo "Usage: $0 [options] target remote_dataset local_dataset
  options:
    -d N  Print N-th log level (1=DEBUG, 2=INFO, 3=WARNING, 4=ERROR)
    -f    Force full sync if conflict is detected between local and remote snapshots
  
  positional:
    target          user@remote, used for SSH
    remote_dataset  The dataset to mirror from
    local_dataset   The dataset to mirror into"
}

main() {
    GETOPT=$(getopt -o=fd: -- $@) || exit 1
    eval set -- "${GETOPT}"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            (-f)
                FORCE_MIRROR=1
                shift 1
                ;;
            (-d)
                LOG_LEVEL=$2
                shift 2
                ;;
            (-h)
                print_usage
                exit 0
                ;;
            (--)
                shift 1
                break
                ;;
        esac
    done

    if [ "$#" -ne "3" ]; then
        echo Invalid number of arguments
        print_usage
        exit 1
    fi

    local TARGET=$1
    local REMOTE_DATASET=$2
    local LOCAL_DATASET=$3

    mirror ${TARGET} ${REMOTE_DATASET} ${LOCAL_DATASET}
    return $?
}

main $*
