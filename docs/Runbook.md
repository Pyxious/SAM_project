# LINKod System Administrator Runbook (Option 1B: Service Lifecycle Control)

## 1. Application Overview & Server Requirements
**LINKod** is a web-based service request and workforce management platform built for Bicol University, serving three distinct roles: **Administrators**, **Workers**, and **Clients**.

### Required Server & Software Stack
* **Operating System:** Ubuntu Server LTS (24.04 / 26.04 LTS, or WSL2 Ubuntu LTS with `systemd=true`)
* **Web Server:** Nginx (`nginx`) listening on TCP port `80`
* **Application Runtime:** PHP 8.3+ (`php-fpm`, `php-mysql`, `php-xml`, `php-mbstring`, `php-curl`, `php-zip`, `php-gd`, `php-bcmath`, `php-intl`), Composer, Node.js & NPM
* **Database Server:** MariaDB / MySQL (`mariadb-server`) listening on `127.0.0.1:3306`

---

## 2. Step-by-Step Installation Guide
1. **Prepare the Configuration File (Root Only, Permissions `600`):**
   ```bash
   sudo mkdir -p /etc/linkod
   sudo cp config/linkod.conf.example /etc/linkod/linkod.conf
   sudo chown root:root /etc/linkod/linkod.conf
   sudo chmod 600 /etc/linkod/linkod.conf
   ```
   *(Edit `/etc/linkod/linkod.conf` with `sudo nano /etc/linkod/linkod.conf` if you wish to customize the database password.)*

2. **Make the Toolkit Scripts Executable:**
   ```bash
   chmod +x scripts/*.sh
   ```

3. **Run the Installation Script:**
   ```bash
   sudo ./scripts/linkod-install.sh
   ```
   The script installs all packages, creates `linkod_db` and `linkod_user`, deploys LINKod to `/var/www/linkod`, runs migrations and asset builds, configures Nginx, and verifies an `HTTP 200` response on `http://localhost`.

---

## 3. Routine Administration Tasks & Schedule

| Frequency | Task | Command |
| :--- | :--- | :--- |
| **Daily** | Check service status, listening ports, and CPU/RAM/Disk use | `sudo ./scripts/linkod-status.sh --save /var/log/linkod/status-$(date +%F).txt` |
| **Before Maintenance** | Switch LINKod to "Temporarily Unavailable" (HTTP 503) | `sudo ./scripts/linkod-maintenance.sh --on` |
| **After Maintenance** | Return LINKod to live production mode (HTTP 200) | `sudo ./scripts/linkod-maintenance.sh --off` |
| **Per Release / Patch** | Back up automatically, apply update, and verify health | `sudo ./scripts/linkod-update.sh /path/to/update-dir` |
| **Emergency Freeze** | Freeze worker processes immediately (`SIGSTOP`) | `sudo ./scripts/linkod-pause.sh --pause` |
| **Resume from Freeze** | Resume frozen worker processes (`SIGCONT`) | `sudo ./scripts/linkod-pause.sh --resume` |
| **Server Reboot / Maint.** | Stop or start the full stack in dependency order | `sudo ./scripts/linkod-service.sh --stop` / `--start` |

---

## 4. Troubleshooting & Manual Recovery (When Something Goes Wrong)

### Scenario A: A Broken Update Fails Verification (Live Demo Scenario)
When `sudo ./scripts/linkod-update.sh <UPDATE_DIR>` detects that the application failed its post-update health check (e.g., `HTTP 500`), it stops immediately and prints the exact backup file path created before the update.

**Manual Restore Steps (By Hand):**
1. Locate the pre-update backup path printed by `linkod-update.sh` (stored in `/var/backups/linkod/`):
   ```bash
   sudo ls -lh /var/backups/linkod/
   ```
2. Extract the verified pre-update application archive back into `/var/www/linkod`:
   ```bash
   sudo tar -xzf /var/backups/linkod/linkod-pre-update-YYYYMMDD-HHMMSS.tar.gz -C /var/www/linkod
   ```
3. Restore ownership and clear cached routes/views:
   ```bash
   sudo chown -R www-data:www-data /var/www/linkod
   sudo -u www-data php /var/www/linkod/artisan optimize:clear
   ```
4. *(If the database also needs to be restored from the pre-update SQL dump)*:
   ```bash
   sudo sh -c '. /etc/linkod/linkod.conf && MYSQL_PWD="$DB_PASS" mysql -u "$DB_USER" "$DB_NAME" < /var/backups/linkod/linkod-db-YYYYMMDD-HHMMSS.sql'
   ```
5. Verify the application is working again:
   ```bash
   curl -I http://localhost
   sudo ./scripts/linkod-status.sh
   ```

### Scenario B: Browser Hangs Indefinitely (No Response)
* **Cause:** Application worker processes may be suspended (`T` state from `kill -STOP`).
* **Fix:** Check `sudo ./scripts/linkod-pause.sh --status` and resume with:
  ```bash
  sudo ./scripts/linkod-pause.sh --resume
  ```

### Scenario C: Users See "LINKod is Temporarily Unavailable" (HTTP 503)
* **Cause:** Application is in Maintenance Mode (`/var/www/linkod/storage/framework/down` exists).
* **Fix:** Disable maintenance mode with:
  ```bash
  sudo ./scripts/linkod-maintenance.sh --off
  ```

---

## 5. Important File, Log, and Backup Locations

| Path | Purpose | Permissions |
| :--- | :--- | :--- |
| `/etc/linkod/linkod.conf` | Toolkit configuration & DB credentials | `600` (`root:root`) |
| `/var/www/linkod` | Deployed LINKod application directory | `750` dirs / `640` files (`www-data:www-data`) |
| `/var/www/linkod/.env` | Laravel runtime environment configuration | `600` (`www-data:www-data`) |
| `/var/www/linkod/storage/logs/laravel.log` | Application error and event log | `664` (`www-data:www-data`) |
| `/var/log/nginx/error.log` | Nginx web server error log | `640` (`www-data:adm`) |
| `/var/backups/linkod/` | Automatic pre-update `.tar.gz` and `.sql` backups | `700` (`root:root`) |
| `/run/linkod.lock` | Active service stack lock file | `640` (`root:root`) |
