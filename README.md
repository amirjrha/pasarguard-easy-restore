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
```

Run the restore wizard:

```bash
curl -fsSL https://raw.githubusercontent.com/amirjrha/pasarguard-easy-restore/main/pg-restore-wizard.sh -o pg-restore-wizard.sh
chmod +x pg-restore-wizard.sh
bash pg-restore-wizard.sh
```

## Notes

After running the script, it will ask you:

- Backup ZIP path
- Panel IP or domain
- Panel port
- Telegram backup settings

## Warning

Do not upload your backup ZIP, `.env`, passwords, Telegram bot token, API keys, or private certificates to GitHub.
