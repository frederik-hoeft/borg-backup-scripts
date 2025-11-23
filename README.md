# Borg Backup Automation

A cron-based backup automation system using BorgBackup with support for multiple remote destinations and Wake-on-LAN functionality.

## Architecture

The system consists of three main components:

- **Core scripts**: `borg-run.sh` orchestrates backup jobs by frequency (daily/weekly/monthly)
- **Job scripts**: Individual backup tasks in `jobs/` directories handle specific services or data
- **Cron wrappers**: Simple scripts that set environment variables and invoke the main runner

## Configuration

### Host Configuration

Copy `borg.hosts.json.template` to `borg.hosts.json` and configure remote backup hosts:

```json
[
    {
        "hostname": "backup-server.domain",
        "port": 22,
        "wake_on_lan_mac": "00:11:22:33:44:55",
        "borg_rsh": "/usr/bin/sshpass -f/root/.ssh/pass -P assphrase /usr/bin/ssh",
        "borg_repo_root": "/path/to/borg/repo"
    }
]
```

### Secrets

Copy `borg.secrets.template` to `borg.secrets` and configure global configurations shared across jobs (e.g., paths and options shared across your jobs). In addition to shared configurations, each job script likely requires its own specific secrets (e.g., borg repository passphrases). Ensure that sensitive information is protected with appropriate 600 file permissions. All executable scripts should be root-owned and non-world-writable.

## Wake-on-LAN Setup

For remote hosts that need to be woken up before backup:

1. **Target Host**: Enable Wake-on-LAN in BIOS and network interface settings and configure borg backup to serve over SSH. You may opt to choose a dockerized borg server setup for easier management, e.g., using the 3rd party provided [`borg-backup`](https://hub.docker.com/r/tgbyte/borg-backup) docker image. Server-side setup is outside the scope of this documentation.
2. **Router/Switch**: Depending on your network architecture, you may need to add static ARP entries to allow WoL packets to be routed correctly. This step is specific to your network setup and operating environment. For example, if using a Linux-based router you might add the following to the post-up section of the relevant network interface:
    ```bash
    post-up /usr/sbin/ip neighbor replace to <backup host IP> dev <egressing network interface to backup host IP> lladdr <backup host MAC>
    ```
    Above ensures that the upstream router can correctly forward the WoL packets to the target host.

3. **Source Host**: Ensure `wakeonlan` package is installed and that you have a way to automatically shut down the target host after backup if desired (e.g., via SSH with command execution restricted to shutdown in `authorized_keys`). Ensure firewalls allow WoL packets and shutdown commands to reach the target host.

## Cron Scheduling

Symlink the cron wrapper scripts (`borg/*.borg.cron`) to your system's cron directory (e.g., `/etc/cron.daily/`, `/etc/cron.weekly/`, `/etc/cron.monthly/`) to schedule automatic backups.

## Job Structure

Backup jobs are organized by frequency in `jobs/daily/`, `jobs/weekly/`, and `jobs/monthly/`. Each job script backs up a specific service or data set to a distinct borg repository and follows the pattern:

1. Source required helper modules (see provided example jobs for reference)
2. Stop services if necessary
3. Perform backup using borg helpers
4. Restore services
5. Clean up resources
