-- Oracle user/security audit
SELECT username, account_status, default_tablespace, profile FROM dba_users ORDER BY username;
SELECT grantee, granted_role, admin_option FROM dba_role_privs ORDER BY grantee;
SELECT grantee, owner, table_name, privilege FROM dba_tab_privs ORDER BY grantee, owner;
