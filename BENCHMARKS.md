# WitFoo Appliance Technical Requirements

## Minimum Hardware Requirements

| WitFoo Appliance | CPU Cores (minimum) | RAM (minimum) |
| --- | :---: | :---: |
| Conductor | 2 CPU | 8GB |
| Reporter | 2 CPU | 16GB |
| Console | 1 CPU | 4GB |
| Analytics All-In-One with Conductor | 6 CPU | 24GB |
| Analytics All-In-One | 4 CPU | 16GB |
| Analytics Data Node | 2 CPU | 8GB |
| Analytics Node | 2 CPU | 6GB |

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
