# Appendix A: Project Proposal and Option Selection Form (Draft)

| Field | Response |
| :--- | :--- |
| **Block and capstone group number** | BSIT 4[A/B] - Group [XX] *(fill in your block & group number)* |
| **Group name (short name based on your capstone project title)** | `LINKod` |
| **Members (name and role)** | • Justin [Last Name] – System Administrator / Lead Scripter<br>• [Member 2 Name] – Service Lifecycle & Update Scripter<br>• [Member 3 Name] – Documentation, Man Page & Runbook Author<br>• [Member 4 Name] – Testing, QA & Live Demo Operator |
| **Capstone application title** | LINKod: Bicol University Service Request and Workforce Management Platform |
| **What the application does and who uses it** | LINKod is a role-based web application connecting Bicol University clients, field workers, and administrators to submit, assign, track, and fulfill campus service requests in real time. |
| **Technology stack (server, language, database)** | Ubuntu Linux LTS, Nginx web server, PHP 8.3+ (Laravel 13 & Livewire 3 via PHP-FPM), MariaDB/MySQL, Node.js/Vite. |
| **Current server (Linux VM, XAMPP on Windows, cloud, none)** | Local Windows development + Ubuntu LTS on WSL2 (`systemd` enabled) / Linux VM. |
| **Laptop that will run your project VM (owner, RAM, free disk)** | Justin's Laptop – [e.g., 16 GB RAM, 50+ GB free disk space], running Ubuntu LTS (`systemd=true`). |
| **First choice (1A, 1B, 1C, or 2)** | **1B** (Service Lifecycle Control) |
| **Second choice (1A, 1B, 1C, or 2)** | **1A** (Operations and Data Protection) |
| **Why this option fits your application** | LINKod relies on a multi-tier service stack (MariaDB -> PHP-FPM -> Nginx) where startup order, zero-data-loss updates with pre-update backups, process suspension (`kill -STOP`/`-CONT`), and user-facing maintenance mode (`HTTP 503`) are essential for production operations. |
| **Planned scripts, and audit areas for Option 2** | 1. `linkod-install.sh` (Clean Ubuntu platform & app deployment)<br>2. `linkod-service.sh` (Ordered start/stop & duplicate prevention)<br>3. `linkod-status.sh` (Service state, ports `80`/`3306`, CPU/RAM/Disk monitor)<br>4. `linkod-update.sh` (Auto `.tar.gz` + SQL backup, verify, update, health check & manual recovery instructions)<br>5. `linkod-pause.sh` (`kill -STOP` and `kill -CONT` process control)<br>6. `linkod-maintenance.sh` (HTTP 503 "temporarily unavailable" toggle) |
| **Risks you expect and how you will handle them** | 1. **Slow/no lab internet during check-offs:** All apt packages, Composer `vendor/`, and compiled NPM assets will be pre-installed and cached on the Ubuntu VM beforehand.<br>2. **Accidental impact on Capstone code:** The IT 123 toolkit uses an isolated snapshot deployed to `/var/www/linkod` with test data only. |
