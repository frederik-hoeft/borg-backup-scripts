# Borg Backup Scripts

A pure-bash backup automation system using BorgBackup with support for multiple remote backup destination hosts, Docker container backups, and Wake-on-LAN functionality, intended for cron integration.

## Overview

This repository contains a collection of bash scripts designed to automate backup operations across multiple remote hosts using BorgBackup. The system includes support for Docker container volume backups, automatic host wake-up via Wake-on-LAN, and flexible scheduling through cron jobs.

## Features

- **Multi-Host Support**: Execute backup operations across multiple remote backup hosts
- **Wake-on-LAN Integration**: Automatically wake up backup hosts when needed and shut them down after completion
- **Docker Container Backups**: Specialized scripts for backing up Docker container volumes
- **Modular Architecture**: Organized helper functions in separate modules for maintainability
- **Flexible Scheduling**: Daily, weekly, and monthly backup job organization with parameter validation
- **Comprehensive Logging**: Detailed logging with verbose mode and error handling
- **Error Recovery**: Graceful error handling with cleanup procedures
- **JSON Configuration**: Host configuration management through JSON files
- **Environment Validation**: Automatic validation of required environment variables

## Project Structure

```
borg/
├── borg.conf                    # Global configuration and environment variables
├── borg-helpers.sh              # Core helper functions and utilities
├── borg-run.sh                  # Main execution script with frequency validation
├── borg.hosts.json.template     # Template for host configuration
├── borg.secrets.template        # Template for sensitive configuration
├── daily.borg.cron             # Daily cron job configuration
├── weekly.borg.cron             # Weekly cron job configuration
├── monthly.borg.cron            # Monthly cron job configuration
├── modules/                     # Modular helper libraries
│   └── docker-helpers.sh        # Docker container management functions
└── jobs/
    ├── daily/                   # Daily backup scripts
    │   ├── overleaf-volumes.sh
    │   ├── passbolt-volumes.sh
    │   └── seafile-volumes.sh
    ├── weekly/                  # Weekly backup scripts
    │   ├── jellyfin-volumes.sh
    │   └── teamspeak-volumes.sh
    └── monthly/                 # Monthly backup scripts (placeholder)
```

## Configuration Files

- **borg.conf**: Contains global environment variables including log file paths, verbose settings, and WOL state directory
- **borg.hosts.json**: Defines backup host configurations including hostnames, ports, MAC addresses, SSH settings, and repository paths
- **borg.secrets**: Contains system configuration data such as the username and path of the Docker user

## Setup Instructions

### 1. Initial Configuration

Copy the template files and customize them:

```bash
cp borg/borg.hosts.json.template borg/borg.hosts.json
cp borg/borg.secrets.template borg/borg.secrets
```

### 2. Host Configuration

Edit `borg/borg.hosts.json` to define your backup hosts:

```json
[
    {
        "hostname": "backup-host.example.com",
        "port": 22,
        "wake_on_lan_mac": "00:11:22:33:44:55",
        // sample, using sshpass to provide the password non-interactively (look for ([Pp])assphrase prompt)
        "borg_rsh": "/usr/bin/sshpass -f/root/.ssh/pass -P assphrase /usr/bin/ssh",
        "borg_repo_root": "/path/to/borg/repositories"
    }
]
```

### 3. Secrets Configuration

Edit `borg/borg.secrets` to set required environment variables:

```bash
export DOCKER_USER='your-docker-user'
export DOCKER_ROOT='/home/your-docker-user'
```

Each backup job also requires its own secrets file (e.g., `jobs/seafile.secrets`) containing the `BORG_PASSPHRASE`:

```bash
export BORG_PASSPHRASE='your-borg-passphrase'
```

Similarly, each backup job is expected to source the `BORG_PASSPHRASE` variable from its own secrets file.

### 4. Dependencies

Ensure the following tools are installed:
- BorgBackup
- jq (for JSON parsing)
- sshpass (for SSH authentication)
- wakeonlan (for Wake-on-LAN functionality)
- Docker (for container management) / optional

Wake-on-LAN functionality requires that the backup hosts support WOL and are configured accordingly. Additionally, static ARP entries may be needed to ensure ARP resolution works correctly, even if the target host is powered off.

### 5. Directory Setup

Create required directories:

```bash
mkdir -p /var/log/borg
mkdir -p /run/borg/wol
```

### 6. Cron Integration

Install cron jobs for automated execution. The main script now validates frequency parameters:

```bash
# Example: Daily backups at 2 AM
0 2 * * * /path/to/borg-backup-scripts/borg/borg-run.sh daily

# Example: Weekly backups on Sunday at 3 AM
0 3 * * 0 /path/to/borg-backup-scripts/borg/borg-run.sh weekly

# Example: Monthly backups on the 1st at 4 AM
0 4 1 * * /path/to/borg-backup-scripts/borg/borg-run.sh monthly
```

Alternatively, symlink the provided cron configuration files to your system's cron directory.

## Environment Variables

### Global Variables (borg.conf)
- `BACKUP_LOG_FILE`: Main log file path
- `BACKUP_LOG_FILE_TEMP`: Temporary log file for cron output
- `BACKUP_WOL_STATE_DIR`: Directory for Wake-on-LAN state files
- `BACKUP_LOG_VERBOSE`: Enable verbose logging (auto-configured based on `BACKUP_SCHEDULED_JOB`)
- `BACKUP_SCHEDULED_JOB`: Indicates scheduled execution (controls verbosity)
- `BORG_HOST_CONFIG`: Path to host configuration JSON file (auto-configured)

### Per-Host Variables (injected by foreach_backup_host)
- `BACKUP_HOST`: Current backup host hostname
- `BACKUP_PORT`: SSH port for the current host
- `BACKUP_MAC`: Wake-on-LAN MAC address
- `BORG_RSH`: SSH command for Borg operations
- `BACKUP_REPO_ROOT`: Root directory for Borg repositories
- `BORG_REPO`: Complete repository URL (when REPOSITORY_NAME is set)

## Error Handling

The system implements multiple levels of error handling:

1. **Script Level**: Individual backup scripts can return exit codes 0 (success), 1 (continue with next script), or 2 (abort all backups)
2. **Host Level**: Failed operations on one host do not affect operations on other hosts
3. **Cleanup Level**: Automatic cleanup of Wake-on-LAN state and container restoration on failures

## Logging

All operations are logged with timestamps and log levels:
- **INFO**: General operational information
- **WARN**: Warning conditions that do not stop execution
- **ERROR**: Error conditions that may stop current operations
- **EXEC**: Command execution logging
- **ABORT/PANIC**: Critical failures requiring immediate attention

Verbose logging can be controlled through the `BACKUP_LOG_VERBOSE` environment variable, with automatic verbose output for interactive sessions and condensed output for cron jobs.