#!/usr/bin/env bash

# set bash options, fail on unset variables, and pipefail
set -uo pipefail
shopt -s nullglob

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

# validate that all required tools are installed
validate_required_tools() {
    local missing_tools=()
    local required_tools=(
        "/usr/bin/realpath"
        "/usr/bin/dirname"
        "/usr/bin/truncate"
        "/usr/bin/tee"
        "/usr/bin/cat"
        "/usr/bin/jq"
        "/usr/bin/borg"
        "/usr/bin/nc"
        "/usr/bin/wakeonlan"
        "/usr/bin/getent"
        "/usr/bin/awk"
        "/usr/bin/sshpass"
        "/usr/bin/ssh"
        "/usr/bin/su"
        "/usr/bin/docker"
        "/usr/bin/ping"
    )
    
    for tool in "${required_tools[@]}"; do
        if [ ! -x "$tool" ]; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "ERROR: The following required tools are missing:"
        printf '  - %s\n' "${missing_tools[@]}"
        echo "Please install the missing tools before running this script."
        exit 1
    fi
}

# validate required tools before proceeding
validate_required_tools

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
foreach_backup_host --capture=no borg_poke_backup_host || try_panic $?

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
    [ -f "${backup_script}" ] && [ -x "${backup_script}" ] || continue
    "${backup_script}" || try_panic $?
done

###############################################################################
#                            </BACKUP DEFINITIONS>                            #
###############################################################################

# clean up any resources
borg_cleanup

info "[EXIT] $(basename "$0") is exiting..."
