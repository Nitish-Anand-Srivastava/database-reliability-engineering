// MongoDB performance checks
use admin;
db.setProfilingLevel(1, { slowms: 200 });

db.getSiblingDB('admin').aggregate([
  { $currentOp: { allUsers: true, localOps: true } },
  { $match: { active: true, secs_running: { $gte: 5 } } },
  { $project: { opid: 1, secs_running: 1, ns: 1, op: 1, command: 1 } }
]);

// Per-collection index usage
db.getSiblingDB('your_db').getCollectionNames().forEach(c => printjson(db.getSiblingDB('your_db')[c].aggregate([{ $indexStats: {} }]).toArray()));
