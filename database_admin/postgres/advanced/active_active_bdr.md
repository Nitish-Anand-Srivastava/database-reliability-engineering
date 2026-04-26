# PostgreSQL Active-Active (BDR/Logical Replication)

## Overview
Active-active replication using logical replication or BDR extensions.

## Key Considerations
- Conflict resolution
- Sequence management
- Write routing

## Sample Setup (Logical Replication)
-- On node1
CREATE PUBLICATION pub_all FOR ALL TABLES;

-- On node2
CREATE SUBSCRIPTION sub_all CONNECTION 'host=node1 dbname=db user=user password=pass' PUBLICATION pub_all;
