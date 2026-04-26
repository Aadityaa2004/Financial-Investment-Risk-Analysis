# System Architecture

## Overview

The Financial Investment Risk Analysis system is a distributed batch processing pipeline
built on Apache Hadoop 3.3.6, deployed across three AWS EC2 instances (t2.medium).
Four Python MapReduce jobs analyze 2.2M LendingClub loan records, and four Go
microservices expose the results via a REST API and interactive dashboard.

## Node Topology

```
                        ┌──────────────────────────────────────────────────┐
                        │           EC2 Master Node (t2.medium)            │
                        │                                                  │
  ┌──────────────────┐  │  ┌──────────────┐    ┌────────────────────────┐ │
  │   Your Browser   │◄─┼─►│  Dashboard   │    │  Hadoop Daemons        │ │
  │                  │  │  │  :3000       │    │  ─ NameNode (:9870)    │ │
  └──────────────────┘  │  └──────────────┘    │  ─ ResourceManager     │ │
                        │                      │    (:8088)             │ │
  ┌──────────────────┐  │  ┌──────────────┐    │  ─ JobHistoryServer    │ │
  │   Curl / Client  │◄─┼─►│ API Gateway  │    │    (:19888)           │ │
  └──────────────────┘  │  │  :8080       │    └────────────────────────┘ │
                        │  └──────┬───────┘                               │
                        │         │                                        │
                        │  ┌──────▼───────┐    ┌────────────────────────┐ │
                        │  │  Orchestrator│    │  Result Aggregator     │ │
                        │  │  :8081       │    │  :8082                 │ │
                        │  │  (submits    │    │  (reads HDFS output    │ │
                        │  │   YARN jobs) │    │   via WebHDFS)         │ │
                        │  └──────────────┘    └────────────────────────┘ │
                        └──────────────────────────────────────────────────┘
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    │     HDFS blocks     │     YARN tasks       │
                    ▼                     ▼                       ▼
       ┌─────────────────────┐    ┌─────────────────────┐
       │  EC2 Worker 1       │    │  EC2 Worker 2       │
       │  (t2.medium)        │    │  (t2.medium)        │
       │                     │    │                     │
       │  DataNode (:9864)   │    │  DataNode (:9864)   │
       │  NodeManager (:8042)│    │  NodeManager (:8042)│
       │  Python mapper.py   │    │  Python mapper.py   │
       │  Python reducer.py  │    │  Python reducer.py  │
       └─────────────────────┘    └─────────────────────┘
```

## Data Pipeline

```
Kaggle CSV (~500MB)
       │
       ▼ hdfs dfs -put
  HDFS Input: /user/hadoop/lendingclub/input/
       │
       ├──► Job 1: mapper.py → sort → reducer.py → HDFS output/job1-grade/
       ├──► Job 2: mapper.py → sort → reducer.py → HDFS output/job2-state/
       ├──► Job 3: mapper.py → sort → reducer.py → HDFS output/job3-employment/
       └──► Job 4: mapper.py → sort → reducer.py → HDFS output/job4-interest/
                                                         │
                                                         ▼ WebHDFS REST
                                              Result Aggregator (Go)
                                                         │
                                                         ▼ HTTP JSON
                                                    API Gateway (Go)
                                                         │
                                                         ▼
                                              Risk Dashboard (HTML/JS)
```

## Service Communication

| From                | To                  | Protocol | Port  | Purpose                    |
|---------------------|---------------------|----------|-------|----------------------------|
| Browser             | API Gateway         | HTTP     | 8080  | REST API calls             |
| Browser             | Dashboard           | HTTP     | 3000  | Dashboard UI               |
| API Gateway         | Job Orchestrator    | HTTP     | 8081  | Proxy job submission       |
| API Gateway         | Result Aggregator   | HTTP     | 8082  | Proxy result reads         |
| Result Aggregator   | NameNode (WebHDFS)  | HTTP     | 9870  | Read MapReduce output      |
| Job Orchestrator    | YARN ResourceManager| Internal | 8032  | Submit streaming jobs      |
| YARN               | MapReduce scripts   | Streaming| N/A   | Execute mapper/reducer     |
| DataNodes          | NameNode            | RPC      | 9000  | Block reporting            |

## Go Microservice Responsibilities

### API Gateway (:8080)
- Single external-facing HTTP server
- Routes: `/health`, `/api/jobs/*`, `/api/results/*`
- Proxies to orchestrator and aggregator
- Applies CORS headers for dashboard fetch() calls

### Job Orchestrator (:8081)
- Manages `JobDefinition` and `JobState` in a `sync.RWMutex`-protected registry
- Runs `hadoop jar streaming.jar` via `os/exec.Cmd`
- Tracks PENDING → RUNNING → COMPLETED | FAILED state machine

### Result Aggregator (:8082)
- Reads HDFS output files via WebHDFS `op=OPEN` REST calls
- Parses 4-column TSV into strongly-typed Go structs
- Computes `RiskSummary` by aggregating across all four jobs
- Called by API Gateway on every `/api/results/*` request (no caching needed for class demo)

### Dashboard (:3000)
- Serves single HTML page embedded via Go's `embed.FS`
- Page uses Chart.js (CDN) for visualization
- Auto-refreshes every 30s via `fetch()` to the API Gateway
- "Run All Jobs" button POSTs to API Gateway → Orchestrator

## Hadoop MapReduce Jobs

| Job | Key      | Value              | Output                              |
|-----|----------|--------------------|-------------------------------------|
| 1   | grade    | 1:default/1:paid   | grade, total, defaults, rate_pct    |
| 2   | state    | 1:default/1:paid   | state, total, defaults, rate_pct    |
| 3   | emp_bucket| 1:default/1:paid  | bucket, total, defaults, rate_pct   |
| 4   | grade    | interest:X/default:1| grade, total, avg_rate, rate_pct  |

All jobs use **1 reducer** to produce a single sorted output file. This is appropriate
for the small output size (7–51 unique keys per job).
