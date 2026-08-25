-- SQL Server login/user audit
SELECT name, type_desc, is_disabled, create_date FROM sys.server_principals WHERE type IN ('S','U','G') ORDER BY name;
SELECT dp.name user_name, dp.type_desc, dp.authentication_type_desc FROM sys.database_principals dp WHERE dp.type IN ('S','U','G') ORDER BY dp.name;
SELECT p.name principal_name, r.name role_name FROM sys.database_role_members drm JOIN sys.database_principals p ON drm.member_principal_id=p.principal_id JOIN sys.database_principals r ON drm.role_principal_id=r.principal_id ORDER BY p.name;
