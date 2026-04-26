# Scheduler Examples (30-min snapshots, 7-day retention)

## Linux cron
```cron
*/30 * * * * /path/to/<db_type>/scripts/run_oneoff.sh >> /path/to/<db_type>/logs/cron.log 2>&1
15 0 * * * /path/to/<db_type>/scripts/cleanup_retention.sh >> /path/to/<db_type>/logs/cleanup.log 2>&1
```

## systemd timer
- Create `run_oneoff.service` and `run_oneoff.timer` with `OnCalendar=*:0/30`.

## Windows Task Scheduler
- Trigger every 30 minutes.
- Action: run `run_oneoff.sh` via Git Bash or equivalent shell.
