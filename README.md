# PasarGuard Easy Restore

Easy restore wizard for PasarGuard backup on a fresh Ubuntu server.

## What it does

- Installs required packages
- Installs Docker if missing
- Finds or downloads PasarGuard backup ZIP
- Restores PasarGuard files
- Restores TimescaleDB database
- Sets panel IP/domain and port
- Starts PasarGuard panel
- Optionally configures Telegram auto backup

## Usage

Upload your backup ZIP to the server:

```bash
scp backup.zip root@SERVER_IP:/root/
