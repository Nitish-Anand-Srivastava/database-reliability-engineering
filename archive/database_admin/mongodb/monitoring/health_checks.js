// MongoDB daily health checks (run in mongosh)
db.adminCommand({ serverStatus: 1 });
db.adminCommand({ replSetGetStatus: 1 });
db.getSiblingDB('admin').runCommand({ listDatabases: 1 });
db.currentOp({ active: true, secs_running: { $gte: 10 } });
