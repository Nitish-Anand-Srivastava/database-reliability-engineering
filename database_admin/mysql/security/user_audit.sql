-- MySQL security audit
SELECT user, host, account_locked, password_expired FROM mysql.user ORDER BY user, host;
SELECT user, host, Select_priv, Insert_priv, Update_priv, Delete_priv, Super_priv FROM mysql.user ORDER BY user, host;
SHOW GRANTS FOR CURRENT_USER;
