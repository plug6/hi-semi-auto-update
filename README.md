# Insight Deploy Script

A single PowerShell script (`deploy.ps1`) that updates and deploys the **Insight backend** and **frontend** apps that already exist on this server, with an interactive menu.

Launched via a `.bat` file, so it takes no command-line flags — everything is asked interactively.

## What it does

For whichever component(s) you choose, the script:

1. Checks whether the remote `main` branch has new commits (`git fetch` + compare HEAD vs `origin/main`). If nothing changed, that component is **skipped** — unless you choose to force it.
2. Pulls the latest code (`git pull`), safely handling any uncommitted local changes.
3. Installs dependencies with `npm ci` (clean, reproducible install from `package-lock.json`).
4. **Backend only:** offers a database step (skip / migrate+seed / fresh install / restore from backup), then restarts the app with PM2.
5. **Frontend only:** builds the React app (`npm run build`), then reloads Nginx (or starts it if it isn't running).
6. Runs a health check against the running app, retrying a few times to give the process a moment to come up.

## Requirements

- PowerShell (run as the user/account that has access to the repos, PM2, and Nginx)
- Git, Node.js/npm, PM2 installed and on `PATH`
- Existing repos at:
  - `C:\apps\insight\backend`
  - `C:\apps\insight\frontend`
- Nginx installed at `D:\nginx-1.28.0\nginx.exe`
- PM2 process name `HI-api` for the backend (or it will be started fresh with that name if missing)
- Backend and frontend repos must have a committed `package-lock.json` (required by `npm ci`)

If any of these paths or names differ on your setup, update the variables at the top of `deploy.ps1`:

```powershell
$BackendPath   = "C:\apps\insight\backend"
$FrontendPath  = "C:\apps\insight\frontend"
$NginxExe      = "D:\nginx-1.28.0\nginx.exe"
$NginxPrefix   = "D:\nginx-1.28.0"
$Pm2AppName    = "HI-api"
$Pm2StartEntry = "src/index.js"
```

## Usage

Run via the `.bat` file (or directly):

```powershell
.\deploy.ps1
```

You'll be prompted:

```
What do you want to update?
  1) Backend
  2) Frontend
  3) Both
Select option [1/2/3] [default 3]:

Force update, skip change check? [y/N]:
```

- **Target:** press Enter for the default (`3` = Both), or type `1`/`2` for a single component.
- **Force:** press Enter or `n` to only update components with new commits. Type `y` to update regardless of whether anything changed.

### Backend database prompt

If you're updating the backend, you'll also see:

```
[3/4] Database setup options:
  1) Skip DB changes
  2) Run DB update (migrations + seed)
  3) Fresh DB install (baseline + seed)
  4) Restore DB from backup
Select option [1/2/3/4] [default 1]:
```

- **1 — Skip:** no DB changes (default).
- **2 — Update:** runs migrations + seed via `node scripts/setup.js --update`.
- **3 — Fresh install:** ⚠️ can destroy existing data. Requires typing `YES` to confirm, then your Postgres password.
- **4 — Restore from backup:** lists files in `db/backups`, lets you pick one (or the latest), requires typing `RESTORE` to confirm.

### Uncommitted local changes

If the script detects uncommitted changes in a repo before pulling, it will warn you and ask you to type `STASH` to auto-stash them and continue, or anything else to abort that component's update safely.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `npm ci` fails immediately | `package-lock.json` missing or out of sync with `package.json` |
| Health check fails after 5 attempts | App crashed on start, wrong port, or firewall/permission issue — check PM2 logs (`pm2 logs HI-api`) or the frontend build output |
| Update aborted with "uncommitted changes" | Someone edited files directly on the server; stash, commit, or discard them before re-running |
| PM2 starts a *new* process instead of restarting | The existing process name doesn't match `$Pm2AppName` — check `pm2 list` |

## Files

- `deploy.ps1` — the deployment script
- (your existing) `deploy.bat` — launches `deploy.ps1`, no flags needed