# Scaling the WitFoo Data Cluster

WitFoo Analytics uses [Apache Cassandra](https://cassandra.apache.org/) as its primary data store, with a schema optimized for Cassandra 5.0+ and Storage Attached Indexing (SAI). The default deployment uses a single-node configuration with `SimpleStrategy` and a replication factor of 1. As your environment grows, deploying multiple Data Nodes provides significant benefits for performance, resilience, and data retention capacity.

## Why Deploy Multiple Data Nodes?

### Horizontal Scalability
Cassandra is designed for linear horizontal scalability. Adding nodes to the cluster increases both storage capacity and read/write throughput proportionally. Unlike vertical scaling (bigger disks, more CPU), horizontal scaling avoids single-node bottlenecks and allows you to grow incrementally as ingestion rates increase.

### Fault Tolerance
With a single node, any hardware failure results in complete data unavailability. A multi-node cluster with a replication factor of 3 maintains full availability even when a node goes down — the remaining nodes continue to serve reads and writes without interruption.

### Improved Read/Write Performance
Cassandra distributes data across nodes using consistent hashing. More nodes means each node handles a smaller share of the total data, reducing per-node load and improving response times for both writes (log ingestion) and reads (queries, investigations, dashboards).

### Data Retention Capacity
Each Data Node adds 1TB–8TB of usable storage to the cluster. A 3-node cluster with 4TB per node provides 12TB of raw capacity. With a replication factor of 3, this gives approximately 4TB of unique data capacity with full redundancy — significantly more retention than a single node.

### Compaction Headroom
Cassandra requires free disk space to perform compaction (merging and cleaning SSTables). Distributing data across multiple nodes ensures that no single node becomes a compaction bottleneck. Remember: the `/data` partition on each node should remain at least **50% free**.

---

## Updating the Replication Strategy

The default WitFoo schema creates the `analytics_v2` keyspace with `SimpleStrategy` and a replication factor of 1:

```cql
CREATE KEYSPACE IF NOT EXISTS analytics_v2
WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1}
AND durable_writes = true;
```

### For Multi-Node Clusters (Single Datacenter)

When running 3 or more Data Nodes in a single datacenter, update the replication factor to 3:

```cql
ALTER KEYSPACE analytics_v2
WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 3};
```

Then run a full repair to replicate existing data to the new nodes:

```bash
nodetool repair -full analytics_v2
```

### For Multi-Datacenter Deployments

If deploying Data Nodes across multiple datacenters, switch to `NetworkTopologyStrategy` for rack/datacenter-aware replication:

```cql
ALTER KEYSPACE analytics_v2
WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'dc1': 3,
  'dc2': 3
};
```

Replace `dc1` and `dc2` with your actual datacenter names as configured in `cassandra-rackdc.properties`. Then run repair:

```bash
nodetool repair -full analytics_v2
```

> **Important:** After changing the replication strategy, also update the `system_auth` keyspace to maintain authentication availability across the cluster:
> ```cql
> ALTER KEYSPACE system_auth
> WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 3};
> ```

---

## Recommended Cluster Sizes

| Cluster Size | Replication Factor | Fault Tolerance | Use Case |
| :---: | :---: | :---: | --- |
| 1 node | 1 | None | Development, evaluation, small deployments |
| 3 nodes | 3 | 1 node failure | Production — standard |
| 5 nodes | 3 | 2 node failures | Production — high availability |
| 6+ nodes | 3 | Multiple failures | Large-scale or multi-datacenter deployments |

> **Note:** Replication factor should not exceed the number of nodes in the cluster. A replication factor of 3 is recommended for all production deployments.

---

## Adding a Data Node to the Cluster

1. Deploy a new WitFoo Appliance and configure it as a **Data Node** role via `setup.sh`
2. Ensure the new node is configured to join the existing cluster (same cluster name and seed nodes)
3. Once the node joins, Cassandra will automatically begin streaming data to it
4. Run `nodetool status` on any node to verify the new node is `UN` (Up/Normal)
5. After the node is fully joined, run `nodetool cleanup` on the **existing** nodes to remove data they are no longer responsible for

---

## Monitoring the Cluster

```bash
# Check cluster status and node health
nodetool status

# View per-node load distribution
nodetool ring

# Check compaction progress
nodetool compactionstats

# View disk usage on /data
df -h /data
```

---

## References

- [Apache Cassandra Architecture Overview](https://cassandra.apache.org/doc/latest/cassandra/architecture/overview.html) — How Cassandra distributes and replicates data across nodes
- [Apache Cassandra — Adding/Removing Nodes](https://cassandra.apache.org/doc/latest/cassandra/operating/topo_changes.html) — Procedures for scaling clusters up and down
- [DataStax — How Data is Distributed Across a Cluster](https://docs.datastax.com/en/cassandra-oss/3.x/cassandra/architecture/archDataDistributeAbout.html) — Consistent hashing and token distribution
- [DataStax — Replication Strategy](https://docs.datastax.com/en/cassandra-oss/3.x/cassandra/architecture/archDataDistributeReplication.html) — SimpleStrategy vs. NetworkTopologyStrategy
- [Apache Cassandra — Repair](https://cassandra.apache.org/doc/latest/cassandra/operating/repair.html) — Full and incremental repair procedures
- [Apache Cassandra — Compaction](https://cassandra.apache.org/doc/latest/cassandra/operating/compaction/index.html) — Why free disk is critical for compaction
