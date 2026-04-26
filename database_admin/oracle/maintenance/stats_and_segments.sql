-- Oracle maintenance checks
SELECT owner, table_name, stale_stats, last_analyzed FROM dba_tab_statistics WHERE stale_stats='YES' FETCH FIRST 100 ROWS ONLY;
SELECT owner, segment_name, segment_type, bytes/1024/1024 size_mb FROM dba_segments ORDER BY bytes DESC FETCH FIRST 50 ROWS ONLY;
SELECT owner, table_name, num_rows, blocks FROM dba_tables WHERE temporary='N' ORDER BY blocks DESC FETCH FIRST 50 ROWS ONLY;
