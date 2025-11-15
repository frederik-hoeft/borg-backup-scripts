# Borg Backup Scripts

A pure-bash backup automation system using BorgBackup with support for multiple remote backup destination hosts, Docker container backups, and Wake-on-LAN functionality, intended for cron integration.

## Overview

This repository contains a collection of bash scripts designed to automate backup operations across multiple remote hosts using BorgBackup. The system includes support for Docker container volume backups, automatic host wake-up via Wake-on-LAN, and flexible scheduling through cron jobs.

## Features

- **Multi-Host Support**: Execute backup operations across multiple remote backup hosts
- **Wake-on-LAN Integration**: Automatically wake up backup hosts when needed and shut them down after completion
- **Docker Container Backups**: Specialized scripts for backing up Docker container volumes
- **Flexible Scheduling**: Daily, weekly, and monthly backup job organization
- **Comprehensive Logging**: Detailed logging with verbose mode and error handling
- **Error Recovery**: Graceful error handling with cleanup procedures
- **JSON Configuration**: Host configuration management through JSON files

## Project Structure

```
borg/
├── borg.conf                    # Global configuration and environment variables
├── borg.helpers                 # Helper functions and utilities
├── borg-run.sh                  # Main execution script
├── borg.hosts.json.template     # Template for host configuration
├── borg.secrets.template        # Template for sensitive configuration
├── daily.borg.cron             # Daily cron job configuration
├── weekly.borg.cron             # Weekly cron job configuration
├── monthly.borg.cron            # Monthly cron job configuration
└── jobs/
    ├── daily/                   # Daily backup scripts (example)
    │   ├── overleaf-volumes.sh
    │   ├── passbolt-volumes.sh
    │   └── seafile-volumes.sh
    ├── weekly/                  # Weekly backup scripts (example)
    │   ├── jellyfin-volumes.sh
    │   └── teamspeak-volumes.sh
    └── monthly/                 # Monthly backup scripts (placeholder)
```

## Core Components

### Configuration Files

- **borg.conf**: Contains global environment variables including log file paths, verbose settings, and WOL state directory
- **borg.hosts.json**: Defines backup host configurations including hostnames, ports, MAC addresses, SSH settings, and repository paths
- **borg.secrets**: Contains system configuration data such as the username and path of the Docker user

### Helper Functions (borg.helpers)

The helper library provides essential functions:

- **Logging Functions**: `info()`, `warn()`, `error()` with configurable verbosity
- **Error Handling**: `abort_current()`, `abort_all()`, `try_panic()` for graceful error management
- **Command Execution**: `capture()` for logging command output and handling exit codes
- **Host Management**: `borg_poke_backup_host()` for Wake-on-LAN and connectivity checks
- **Multi-Host Execution**: `foreach_backup_host()` for executing commands across all configured hosts

### Backup Job Scripts

Each backup script follows a standard pattern:
1. Container shutdown and volume backup
2. BorgBackup repository operations (create, prune, compact)
3. Container restoration
4. Error handling and cleanup

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

Similarly, each backup job is expected to source the `BORG_PASSPHRASE` variable from its own secrets file.

### 4. Dependencies

Ensure the following tools are installed:
- BorgBackup
- jq (for JSON parsing)
- sshpass (for SSH authentication)
- wakeonlan (for Wake-on-LAN functionality)
- Docker (for container management)

Wake-on-LAN functionality requires that the backup hosts support WOL and are configured accordingly. Additionally, static ARP entries may be needed to ensure ARP resolution works correctly, even if the target host is powered off.

### 5. Directory Setup

Create required directories:

```bash
mkdir -p /var/log/borg
mkdir -p /run/borg/wol
```

### 6. Cron Integration

Install cron jobs for automated execution, e.g., by symlinking the cron configuration files to your system's cron directory.

## Environment Variables

### Global Variables (borg.conf)
- `BACKUP_LOG_FILE`: Main log file path
- `BACKUP_LOG_FILE_TEMP`: Temporary log file for cron output
- `BACKUP_WOL_STATE_DIR`: Directory for Wake-on-LAN state files
- `BACKUP_LOG_VERBOSE`: Enable verbose logging
- `BACKUP_SCHEDULED_JOB`: Indicates scheduled execution

### Per-Host Variables (injected by foreach_backup_host)
- `BACKUP_HOST`: Current backup host hostname
- `BACKUP_PORT`: SSH port for the current host
- `BACKUP_MAC`: Wake-on-LAN MAC address
- `BORG_RSH`: SSH command for Borg operations
- `BACKUP_REPO_ROOT`: Root directory for Borg repositories
- `BORG_REPO`: Complete repository URL (when REPOSITORY_NAME is set)

## Security Considerations

- The `borg.hosts.json` and `*.secrets` files are automatically excluded from version control via `.gitignore`
- SSH authentication is handled through sshpass with password files
- Wake-on-LAN MAC addresses and internal hostnames are considered sensitive information
- Log files may contain sensitive information and should be properly secured

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