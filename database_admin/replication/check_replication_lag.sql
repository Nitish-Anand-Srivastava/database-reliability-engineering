SELECT client_addr, state, sync_state, write_lag, replay_lag
FROM pg_stat_replication;