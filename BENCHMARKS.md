# WitFoo Appliance Technical Requirements

## Minimum Hardware Requirements

| WitFoo Appliance | CPU Cores (minimum) | RAM (minimum) |
| --- | :---: | :---: |
| Conductor | 4 CPU | 8GB |
| Reporter | 8 CPU | 32GB |
| Console | 4 CPU | 8GB |
| Precinct All-In-One | 8 CPU | 32GB |
| Precinct Data Node | 4 CPU | 12GB |
| Precinct Streamer Node | 4 CPU | 12GB |
| Precinct Mgmt Node | 4 CPU | 8GB |

---

## Conductor Benchmarks

The following table shows tested processor configurations and their performance at various message ingestion rates.

| Processor | vCPU | CPU Cores | Threads Per Core | Mem GB | 300 msg/s | 800 msg/s | 2000 msg/s | 4500 msg/s | 7500 msg/s |
| --- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| AMD EPYC 7R13 | 4 | 2 | 2 | 8 | GOOD | GOOD | LIMIT | NA | NA |
| AMD EPYC 7R13 | 8 | 4 | 2 | 16 | GOOD | GOOD | GOOD | LIMIT | NA |
| AMD EPYC 9R45 | 4 | 4 | 1 | 8 | GOOD | GOOD | GOOD | GOOD | LIMIT |
| AMD EPYC 9R45 | 8 | 8 | 1 | 16 | GOOD | GOOD | GOOD | GOOD | GOOD |
| Intel Xeon Ice Lake | 4 | 2 | 2 | 8 | GOOD | GOOD | LIMIT | NA | NA |
| Intel Xeon Ice Lake | 8 | 4 | 2 | 16 | GOOD | GOOD | GOOD | LIMIT | NA |
| Intel Xeon Granite Rapids | 4 | 2 | 2 | 8 | GOOD | GOOD | GOOD | GOOD | OVER |
| Intel Xeon Granite Rapids | 8 | 4 | 2 | 16 | GOOD | GOOD | GOOD | GOOD | LIMIT |

### Rating Legend

| Rating | Description |
| --- | --- |
| **GOOD** | Minimal to moderate stress on processors |
| **LIMIT** | Perpetual 80–90% processor use |
| **OVER** | Processor cores maxed out; not sustainable |
| **NA** | Configuration not applicable for this throughput level |

---

*Source: [WitFoo Appliance Technical Requirements](https://witfoo.zendesk.com/hc/en-us/articles/46342127646739-WitFoo-Appliance-Technical-Requirements)*
