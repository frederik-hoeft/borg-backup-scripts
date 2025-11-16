#!/usr/bin/env bash

# set bash options, fail on unset variables, and pipefail
set -uo pipefail

# require single parameter (daily, weekly, monthly)
if [ "$#" -ne 1 ]; then
    echo "Usage: $(basename "$0") <daily|weekly|monthly>"
    exit 1
fi
BACKUP_FREQUENCY="$1"
# validate parameter using simple case statement
case "${BACKUP_FREQUENCY}" in
    daily|weekly|monthly)
        ;;
    *)
        echo "Invalid backup frequency: ${BACKUP_FREQUENCY}. Must be one of: daily, weekly, monthly."
        exit 1
        ;;
esac

# the directory of this script
export BACKUP_SCRIPT_HOME="$(/usr/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")")"
# the directory of the jobs to run
export BACKUP_SCRIPT_JOBS="${BACKUP_SCRIPT_HOME}/jobs"

# source config and helper functions
. "${BACKUP_SCRIPT_HOME}/borg.conf"
. "${BACKUP_SCRIPT_HOME}/borg-helpers.sh"
. "${BACKUP_SCRIPT_HOME}/borg.secrets"

# clear the log file used for capturing output
/usr/bin/truncate -s0 "${BACKUP_LOG_FILE_TEMP}"

info "[START] $(basename "$0") is initializing..."
info 'Waking up backup hosts...'

# ensure BACKUP_WOL_STATE_DIR is set and exists
if [ -z "${BACKUP_WOL_STATE_DIR}" ]; then
    error "BACKUP_WOL_STATE_DIR is not set in borg.conf"
    exit 1
fi
mkdir -p "${BACKUP_WOL_STATE_DIR}"

# see if remote hosts are up
foreach_backup_host borg_poke_backup_host || try_panic $?

info 'Ok. Proceeding with backup...'

###############################################################################
#                            <BACKUP DEFINITIONS>                             #
###############################################################################

# run all backup scripts set up for this frequency, only considering .sh files
# exit code must be as follows:
# 0: success
# 1: script failed, but backup should continue with subsequent scripts
# 2: script failed, and backup should stop immediately
for backup_script in "${BACKUP_SCRIPT_JOBS}/${BACKUP_FREQUENCY}/"*.sh; do
    [ -e "$backup_script" ] || continue
    "${backup_script}" || try_panic $?
done

###############################################################################
#                            </BACKUP DEFINITIONS>                            #
###############################################################################

# clean up any resources
borg_cleanup

info "[EXIT] $(basename "$0") is exiting..."
