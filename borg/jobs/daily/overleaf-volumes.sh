#!/usr/bin/env bash

# set bash options, fail on unset variables, and pipefail
set -uo pipefail

this_script_dir="$(/usr/bin/dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"
. "${BACKUP_SCRIPT_HOME}/borg-helpers.sh" || exit 2
. "${this_script_dir}/overleaf.secrets" || abort_current

require_borg_passphrase

container_name='overleaf'
container_root="${DOCKER_ROOT}/containers/${container_name}"
volume_root="${DOCKER_ROOT}/volumes/${container_name}"

restore_current() {
    unset_borg_passphrase
    info "Attempting to start '${container_name}' docker container group..."
    capture /usr/bin/su -c "${container_root}/bin/docker-compose up -d" "${DOCKER_USER}" || abort_current
    info "Successfully started '${container_name}' docker container group"
}

info "Attempting to stop '${container_name}' docker container group..."

# bring down container group (specific to overleaf setup)
capture /usr/bin/su -c "${container_root}/bin/docker-compose down" "${DOCKER_USER}" || abort_current

info 'Starting backup'

export REPOSITORY_NAME="${container_name}"

foreach_backup_host --capture=yes /usr/bin/borg create  \
    --show-rc                                           \
    --stats                                             \
    --compression zlib                                  \
    --exclude-caches                                    \
    --exclude '*/mongo/diagnostic.data/*'               \
    --exclude '*/sharelatex/tmp/*'                      \
    --exclude '*/sharelatex/data/cache/*'               \
    --exclude '*/sharelatex/data/compiles/*'            \
    --exclude '*/sharelatex/data/output/*'              \
                                                        \
    ::"${container_name}-{now}"                         \
    "${volume_root}" || {
        restore_current
        abort_current
    }

info 'Pruning repository'

foreach_backup_host --capture=yes /usr/bin/borg prune   \
    --list                                              \
    --glob-archives "${container_name}-*"               \
    --show-rc                                           \
    --keep-daily    30                                  \
    --keep-weekly   12                                  \
    --keep-monthly  12 || {
        restore_current
        abort_current
    }

# actually free repo disk space by compacting segments
info 'Compacting repository'

foreach_backup_host --capture=yes /usr/bin/borg compact --show-rc || {
    restore_current
    abort_current
}

restore_current