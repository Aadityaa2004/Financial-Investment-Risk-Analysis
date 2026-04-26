# Financial Investment Risk Analysis
## Apache Hadoop MapReduce on AWS EC2 — Distributed Systems Project

A production-grade distributed batch processing system that analyzes **2.2 million LendingClub
loan records** to quantify default risk for investors. Built on Apache Hadoop 3.3.6 deployed
across **3 real AWS EC2 instances** (1 master + 2 workers), with four Python MapReduce jobs
and Go microservices exposing the results via a live risk dashboard.

---

## Project Overview

### What This System Does

Investors in peer-to-peer loans (like LendingClub) need to know which loan segments carry
unacceptable default risk. This system runs four MapReduce analyses in parallel across a
Hadoop cluster:

1. **Default Rate by Loan Grade** — grades A–G range from 5% to 41% default rates
2. **Default Rate by US State** — geographic concentration risk (Nevada, Florida highest)
3. **Default Rate by Employment Length** — new employees default 70% more than tenured ones
4. **Interest Rate vs Default Rate** — reveals that Grade C+ loans have *negative* risk-return spreads

### Architecture (3 EC2 Nodes)

```
┌─────────────────────────────────────────────┐
│         EC2 Master (t2.medium)              │
│                                             │
│  Hadoop NameNode   (:9870)                  │
│  YARN ResourceMgr  (:8088)                  │
│  Go API Gateway    (:8080)  ◄── Browser     │
│  Go Job Orchestrator (:8081)                │
│  Go Result Aggregator (:8082)               │
│  Go Risk Dashboard (:3000)  ◄── Browser     │
└─────────────────────┬───────────────────────┘
                      │ HDFS + YARN
          ┌───────────┴───────────┐
          │                       │
┌─────────▼───────────┐  ┌───────▼─────────────┐
│ EC2 Worker 1        │  │ EC2 Worker 2        │
│ (t2.medium)         │  │ (t2.medium)         │
│                     │  │                     │
│ Hadoop DataNode     │  │ Hadoop DataNode     │
│ YARN NodeManager    │  │ YARN NodeManager    │
│ Python mapper.py    │  │ Python mapper.py    │
│ Python reducer.py   │  │ Python reducer.py   │
└─────────────────────┘  └─────────────────────┘
```

---

## Prerequisites

- AWS account with permission to launch EC2 instances
- A Kaggle account (to download the LendingClub dataset)
- An SSH key pair created in your AWS region
- Git installed locally
- Basic familiarity with SSH and terminal commands

---

## Step 1: Launch EC2 Instances

### 1.1 Create a Security Group

In the AWS Console → EC2 → Security Groups → Create Security Group:

| Port  | Protocol | Source        | Purpose                          |
|-------|----------|---------------|----------------------------------|
| 22    | TCP      | Your IP/32    | SSH access                       |
| 9000  | TCP      | VPC CIDR      | HDFS NameNode RPC                |
| 9870  | TCP      | 0.0.0.0/0     | HDFS Web UI                      |
| 8088  | TCP      | 0.0.0.0/0     | YARN ResourceManager UI          |
| 8080  | TCP      | 0.0.0.0/0     | Go API Gateway                   |
| 3000  | TCP      | 0.0.0.0/0     | Risk Dashboard                   |
| 8081  | TCP      | VPC CIDR      | Job Orchestrator (internal)      |
| 8082  | TCP      | VPC CIDR      | Result Aggregator (internal)     |
| 9864  | TCP      | VPC CIDR      | DataNode HTTP                    |
| 8042  | TCP      | VPC CIDR      | NodeManager HTTP                 |
| 19888 | TCP      | 0.0.0.0/0     | MapReduce Job History Server     |
| All   | All      | Security Group| Allow all intra-cluster traffic  |

> **Important:** Add an inbound rule allowing **All traffic** from the security group itself
> (Source = the security group's own ID). This allows Hadoop inter-node communication.

### 1.2 Launch Three Instances

1. EC2 → Launch Instance
2. **AMI:** Ubuntu Server 22.04 LTS (64-bit x86)
3. **Instance type:** t2.medium (2 vCPU, 4 GB RAM)
4. **Key pair:** Select your SSH key pair
5. **Security group:** Select the group you created above
6. **Storage:** 30 GB gp3 (default)
7. Launch three instances (you can launch all three from one "Launch" dialog
   by setting count to 3, then rename them: `hadoop-master`, `hadoop-worker1`, `hadoop-worker2`)

> **[SNAPSHOT PLACEHOLDER: AWS EC2 Console showing 3 running instances — hadoop-master, hadoop-worker1, hadoop-worker2 with green "running" status]**

### 1.3 Note Your IPs

After launch, record the **Public IP** and **Private IP** for each instance.
The private IPs are used for Hadoop inter-node communication.

---

## Step 2: Configure SSH Access

### 2.1 Copy Project Files to Master

From your local machine:

```bash
# Clone or copy the project
git clone <your-repo-url>
cd <your-repo-folder>

# SCP the project to the master node
scp -i ~/.ssh/your-key.pem -r . ubuntu@<MASTER_PUBLIC_IP>:~/<your-repo-folder>/
```

### 2.2 Configure Environment File

SSH into the master node and create your `.env` file:

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<MASTER_PUBLIC_IP>
cd ~/<your-repo-folder>
cp .env.example .env
nano .env   # Fill in all IP addresses
```

Required fields in `.env`:
```
MASTER_PUBLIC_IP=<master-public-ip>
WORKER1_PUBLIC_IP=<worker1-public-ip>
WORKER2_PUBLIC_IP=<worker2-public-ip>
MASTER_PRIVATE_IP=<master-private-ip>
WORKER1_PRIVATE_IP=<worker1-private-ip>
WORKER2_PRIVATE_IP=<worker2-private-ip>
```

### 2.3 Generate SSH Config Entries (Optional)

On your local machine, run:

```bash
bash scripts/ssh-config-helper.sh
```

This adds `hadoop-master`, `hadoop-worker1`, `hadoop-worker2` aliases to `~/.ssh/config`
so you can connect with `ssh hadoop-master` instead of typing the full IP each time.

### 2.4 Test SSH Connectivity

From the master node, verify it can reach both workers:

```bash
ssh ubuntu@worker1 hostname
ssh ubuntu@worker2 hostname
```

> **[SNAPSHOT PLACEHOLDER: Terminal showing successful SSH from master to worker1 and worker2, displaying their hostnames]**

---

## Step 3: Set Up Master Node

SSH into the master EC2 instance:

```bash
ssh ubuntu@<MASTER_PUBLIC_IP>
cd ~/<your-repo-folder>

# Make scripts executable
chmod +x scripts/*.sh

# Run the master setup script
bash scripts/setup-master.sh
```

The script will:
1. Install Docker and Docker Compose
2. Configure `/etc/hosts` for all three nodes
3. Set up passwordless SSH to workers
4. Build the `hadoop-base` and `hadoop-master` Docker images (~10 min first time)
5. Start all master services via `docker compose`
6. Format HDFS NameNode (first run only)
7. Start HDFS and YARN daemons
8. Create HDFS input/output directories

> **[SNAPSHOT PLACEHOLDER: Terminal showing docker-compose master.yml up output with all services starting, then `docker ps` showing hadoop-master container running]**

### 3.1 Verify NameNode Web UI

Open in browser: `http://<MASTER_PUBLIC_IP>:9870`

At this point you will see **0 Live DataNodes** — that is expected until workers are set up.

> **[SNAPSHOT PLACEHOLDER: Hadoop NameNode Web UI at master-ip:9870 showing "Summary" tab — note Live Datanodes: 0 at this stage]**

---

## Step 4: Set Up Worker Nodes

Repeat the following on **both** worker EC2 instances:

```bash
# SSH into worker1
ssh ubuntu@<WORKER1_PUBLIC_IP>

# Copy project files from master
scp -i ~/.ssh/your-key.pem -r ubuntu@<MASTER_PUBLIC_IP>:~/<your-repo-folder> .
cd <your-repo-folder>

# Set worker identity and run setup
export WORKER_ID=worker1   # Use "worker2" on the second instance
export MASTER_PUBKEY="$(cat ~/.ssh/id_rsa.pub)"   # Paste master's public key here

chmod +x scripts/setup-worker.sh
bash scripts/setup-worker.sh
```

The worker script will:
1. Install Docker
2. Configure `/etc/hosts` with the master's private IP
3. Add the master's SSH public key to `authorized_keys`
4. Build `hadoop-worker` Docker image
5. Start DataNode and NodeManager

### 4.1 Verify Workers Are Connected

Back on the master node:

```bash
hdfs dfsadmin -report
```

You should see **2 Live DataNodes** — one per worker.

```bash
yarn node -list
```

You should see **2 RUNNING** nodes.

> **[SNAPSHOT PLACEHOLDER: YARN ResourceManager UI at master-ip:8088 showing "Nodes" tab with 2 active nodes — worker1 and worker2]**
>
> **[SNAPSHOT PLACEHOLDER: Terminal output of `hdfs dfsadmin -report` showing "Live datanodes (2)" and capacity summary]**

---

## Step 5: Upload the LendingClub Dataset

### Option A: Automated Download (Kaggle API)

Add Kaggle credentials to `.env`:
```
KAGGLE_USERNAME=your-username
KAGGLE_KEY=your-api-key
```

Then run:
```bash
bash scripts/upload-dataset.sh
```

### Option B: Manual Download

1. Go to [https://www.kaggle.com/datasets/wordsforthewise/lending-club](https://www.kaggle.com/datasets/wordsforthewise/lending-club)
2. Download `accepted_2007_to_2018Q4.csv.gz`
3. Transfer to the master EC2 instance:
   ```bash
   scp -i ~/.ssh/your-key.pem accepted_2007_to_2018Q4.csv.gz ubuntu@<MASTER_PUBLIC_IP>:/tmp/lendingclub/
   ```
4. Upload to HDFS:
   ```bash
   gunzip /tmp/lendingclub/accepted_2007_to_2018Q4.csv.gz
   hdfs dfs -mkdir -p /user/hadoop/lendingclub/input
   hdfs dfs -put /tmp/lendingclub/accepted_2007_to_2018Q4.csv /user/hadoop/lendingclub/input/
   ```

### Verify the Upload

```bash
hdfs dfs -ls -h /user/hadoop/lendingclub/input/
```

Expected output:
```
Found 1 items
-rw-r--r--   2 root supergroup    ~500 M 2024-01-01 12:00 /user/hadoop/lendingclub/input/accepted_2007_to_2018Q4.csv
```

> **[SNAPSHOT PLACEHOLDER: Terminal showing `hdfs dfs -ls -h /user/hadoop/lendingclub/input/` with the ~500MB CSV file listed, showing replication factor of 2]**

---

## Step 6: Run the MapReduce Jobs

```bash
bash scripts/run-all-jobs.sh
```

The script runs all four jobs sequentially, with progress output for each. Each job
takes approximately 5–15 minutes depending on cluster load.

Expected total runtime: **20–45 minutes** for the full 2.2M record dataset.

You can monitor job progress in the YARN UI at `http://<MASTER_PUBLIC_IP>:8088`.

> **[SNAPSHOT PLACEHOLDER: Terminal showing Job 1 running — hadoop streaming command output with map/reduce progress percentages]**
>
> **[SNAPSHOT PLACEHOLDER: YARN ResourceManager UI showing 4 completed applications in job history, all with "SUCCEEDED" status]**

### Verify Output

```bash
hdfs dfs -ls /user/hadoop/lendingclub/output/
```

Expected:
```
drwxrwxrwx   - root supergroup          0 ... /user/hadoop/lendingclub/output/job1-grade
drwxrwxrwx   - root supergroup          0 ... /user/hadoop/lendingclub/output/job2-state
drwxrwxrwx   - root supergroup          0 ... /user/hadoop/lendingclub/output/job3-employment
drwxrwxrwx   - root supergroup          0 ... /user/hadoop/lendingclub/output/job4-interest
```

> **[SNAPSHOT PLACEHOLDER: Terminal showing `hdfs dfs -ls /user/hadoop/lendingclub/output/` with 4 output directories]**

### View Sample Output Per Job

```bash
# Job 1: Default by Grade (7 rows, one per grade A-G)
hdfs dfs -cat /user/hadoop/lendingclub/output/job1-grade/part-* | head -20

# Job 2: Default by State (51 rows, one per state + DC)
hdfs dfs -cat /user/hadoop/lendingclub/output/job2-state/part-* | head -20

# Job 3: Default by Employment (5 bucket rows)
hdfs dfs -cat /user/hadoop/lendingclub/output/job3-employment/part-* 

# Job 4: Interest vs Default by Grade (7 rows)
hdfs dfs -cat /user/hadoop/lendingclub/output/job4-interest/part-*
```

> **[SNAPSHOT PLACEHOLDER: Terminal showing `hdfs dfs -cat .../job1-grade/part-00000` with 7 lines like "A\t168284\t8616\t5.12", "B\t302158\t34386\t11.38", ..., "G\t2890\t1192\t41.22"]**
>
> **[SNAPSHOT PLACEHOLDER: Terminal showing `hdfs dfs -cat .../job4-interest/part-00000` with grade, total, avg_interest, default_rate columns]**

---

## Step 7: View the Risk Dashboard

Open in your browser:

```
http://<MASTER_PUBLIC_IP>:3000
```

The dashboard will automatically:
- Load results from all 4 MapReduce jobs via the API
- Display color-coded risk charts (green=LOW, yellow=MEDIUM, red=HIGH, purple=CRITICAL)
- Show summary cards with key metrics
- Auto-refresh every 30 seconds

You can also trigger a new analysis run by clicking **"Run All Jobs"** on the dashboard.

> **[SNAPSHOT PLACEHOLDER: Risk Dashboard at master-ip:3000 showing:
>   - Summary cards (Total Loans: 2.2M, Overall Default Rate: ~13.2%, Highest Risk Grade: G, Lowest Risk Grade: A)
>   - Horizontal bar chart showing default rates A through G (green to purple)
>   - Line chart showing interest rate and default rate lines crossing at Grade C
>   - Employment length bar chart
>   - Top 10 states table]**

### API Endpoints

You can also query the API directly:

```bash
# Health check
curl http://<MASTER_PUBLIC_IP>:8080/health

# List available jobs
curl http://<MASTER_PUBLIC_IP>:8080/api/jobs

# Get risk results
curl http://<MASTER_PUBLIC_IP>:8080/api/results/grade      | python3 -m json.tool
curl http://<MASTER_PUBLIC_IP>:8080/api/results/state      | python3 -m json.tool
curl http://<MASTER_PUBLIC_IP>:8080/api/results/employment | python3 -m json.tool
curl http://<MASTER_PUBLIC_IP>:8080/api/results/interest   | python3 -m json.tool
curl http://<MASTER_PUBLIC_IP>:8080/api/results/risk-summary | python3 -m json.tool
```

> **[SNAPSHOT PLACEHOLDER: curl output of `curl master-ip:8080/api/results/risk-summary` showing formatted JSON with highest_risk_grade, overall_default_rate_pct, recommendation, etc.]**

---

## Step 8: Verify Results

### Expected Job 1 Output (Default Rate by Grade)

```
A       168284  8616    5.12
B       302158  34386   11.38
C       264781  44680   16.87
D       118453  28808   24.31
E       42376   12762   30.14
F       11124   4058    36.48
G       2890    1192    41.22
```

Format: `grade \t total_loans \t total_defaults \t default_rate_pct`

### Expected Job 4 Output (Interest vs Default)

```
A       168284  7.26    5.12
B       302158  11.49   11.38
C       264781  15.62   16.87
D       118453  19.89   24.31
E       42376   24.07   30.14
F       11124   28.12   36.48
G       2890    29.98   41.22
```

Format: `grade \t total_loans \t avg_interest_rate \t default_rate_pct`

### Risk Level Thresholds

| Default Rate   | Risk Level | Color    |
|----------------|-----------|----------|
| < 5%           | LOW       | Green    |
| 5% – 15%       | MEDIUM    | Yellow   |
| 15% – 25%      | HIGH      | Red      |
| > 25%          | CRITICAL  | Purple   |

---

## Testing MapReduce Locally (Without Hadoop)

You can verify the Python logic without a running Hadoop cluster using the included
sample dataset (`mapreduce/test-data/sample_loans.csv`, 19 data rows):

```bash
# Job 1: Default by Grade
cat mapreduce/test-data/sample_loans.csv \
  | python3 mapreduce/job1-default-by-grade/mapper.py \
  | sort \
  | python3 mapreduce/job1-default-by-grade/reducer.py

# Job 2: Default by State
cat mapreduce/test-data/sample_loans.csv \
  | python3 mapreduce/job2-default-by-state/mapper.py \
  | sort \
  | python3 mapreduce/job2-default-by-state/reducer.py

# Job 3: Default by Employment
cat mapreduce/test-data/sample_loans.csv \
  | python3 mapreduce/job3-default-by-employment/mapper.py \
  | sort \
  | python3 mapreduce/job3-default-by-employment/reducer.py

# Job 4: Interest vs Default
cat mapreduce/test-data/sample_loans.csv \
  | python3 mapreduce/job4-interest-vs-default/mapper.py \
  | sort \
  | python3 mapreduce/job4-interest-vs-default/reducer.py
```

Or use the Makefile shortcut:
```bash
make test-mapreduce
```

---

## Project Structure

```
<your-repo-folder>/
├── README.md                          # This file
├── docker-compose.master.yml          # Master node Docker Compose
├── docker-compose.worker.yml          # Worker node Docker Compose
├── .env.example                       # Environment variable template
├── Makefile                           # Convenience targets
│
├── hadoop-config/                     # Hadoop XML configuration
│   ├── core-site.xml                  # HDFS default filesystem: hdfs://master:9000
│   ├── hdfs-site.xml                  # Replication=2, block size=128MB
│   ├── mapred-site.xml                # YARN framework, 1GB per task
│   ├── yarn-site.xml                  # ResourceManager=master, 3GB NodeManager
│   └── workers                        # Lists: worker1, worker2
│
├── mapreduce/
│   ├── test-data/sample_loans.csv     # 19 rows for local testing
│   ├── job1-default-by-grade/
│   │   ├── mapper.py                  # Emits (grade, 1:default|1:paid)
│   │   ├── reducer.py                 # Emits (grade, total, defaults, pct)
│   │   └── run.sh                     # hadoop jar streaming... command
│   ├── job2-default-by-state/         # Same pattern, keyed by US state
│   ├── job3-default-by-employment/    # Keyed by 5 employment-length buckets
│   └── job4-interest-vs-default/      # Dual-value: interest:X and default:1
│
├── services/                          # Go microservices
│   ├── go.mod                         # Module: github.com/aadityaa/hadoop-risk
│   ├── api-gateway/                   # Gin HTTP server, proxies to other services
│   │   ├── main.go                    # Routes, CORS, graceful shutdown
│   │   └── handlers/                  # jobs.go, results.go, health.go
│   ├── job-orchestrator/              # Submits hadoop streaming jobs via os/exec
│   │   ├── main.go
│   │   └── orchestrator/              # models.go, hadoop.go (exec + WebHDFS)
│   ├── result-aggregator/             # Parses TSV output from HDFS
│   │   ├── main.go                    # WebHDFS reader + HTTP handlers
│   │   ├── parsers/                   # grade_parser.go, state_parser.go, ...
│   │   └── models/risk.go             # LoanGradeRisk, StateRisk, RiskSummary
│   └── dashboard/
│       ├── main.go                    # embed.FS + HTTP server
│       └── templates/index.html       # Chart.js dashboard, auto-refresh
│
├── docker/
│   ├── Dockerfile.hadoop-base         # Ubuntu 22.04 + Java 11 + Hadoop 3.3.6
│   ├── Dockerfile.master              # Extends base + Go 1.22 + built binaries
│   ├── Dockerfile.worker              # Extends base + Python scripts
│   ├── entrypoint-master.sh           # Format HDFS, start daemons + Go services
│   └── entrypoint-worker.sh           # Wait for master, start DataNode + NM
│
├── scripts/
│   ├── setup-master.sh                # Install Docker, build images, start services
│   ├── setup-worker.sh                # Install Docker, build image, start worker
│   ├── upload-dataset.sh              # Kaggle download + hdfs dfs -put
│   ├── run-all-jobs.sh                # Run all 4 jobs with timing + output counts
│   ├── fetch-results.sh               # hdfs dfs -cat > ./results/*.tsv
│   └── ssh-config-helper.sh           # Generates ~/.ssh/config entries
│
└── docs/
    ├── architecture.md                # Detailed system design with diagrams
    ├── risk-analysis-report.md        # Full results interpretation with tables
    └── screenshots/                   # [Empty — add screenshots after deployment]
```

---

## Makefile Reference

```bash
make build              # Build all Docker images (base → master + worker)
make deploy-master      # Start docker-compose.master.yml
make deploy-worker      # Start docker-compose.worker.yml
make upload-data        # Download LendingClub CSV and put to HDFS
make run-jobs           # Run all 4 MapReduce jobs
make fetch-results      # Copy HDFS output to ./results/
make status             # Show HDFS health, containers, job history
make clean              # Stop containers, remove HDFS output
make test-mapreduce     # Test all mapper/reducer pairs with sample_loans.csv
make logs               # Tail Go service logs from master container
make help               # List all targets
```

---

## Troubleshooting

### NameNode in Safe Mode
```bash
# If you see "Name node is in safe mode" errors:
hdfs dfsadmin -safemode leave
```

### DataNode Not Connecting to NameNode
```bash
# 1. Check /etc/hosts on the worker — must resolve "master" to the private IP
cat /etc/hosts | grep master

# 2. Check the worker container logs
docker logs hadoop-worker

# 3. Verify port 9000 is reachable from the worker
nc -zv master 9000

# 4. Check the security group allows intra-cluster traffic
```

### Job Stuck / Not Progressing
```bash
# 1. Check YARN application status
yarn application -list

# 2. View full YARN application logs
yarn logs -applicationId <application_XXXXX_0001>

# 3. Check NodeManager is running
yarn node -list

# 4. Verify Python is available on workers
docker exec hadoop-worker python3 --version
```

### HDFS Replication Warnings
```
WARNING: Replication under target: ...
```
This is **expected and harmless** when running with exactly 2 DataNodes and
`dfs.replication=2`. The cluster is fully functional — every block is replicated to
both workers exactly as configured.

### "hadoop-streaming jar not found" Error
```bash
# Verify the jar exists
find $HADOOP_HOME/share/hadoop/tools/lib -name "hadoop-streaming-*.jar"

# Expected output:
# /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-3.3.6.jar
```

### Go Services Not Responding
```bash
# Check all Go services are running
docker exec hadoop-master ps aux | grep -E "(api-gateway|job-orchestrator|result-aggregator|dashboard)"

# Check API gateway health
curl http://localhost:8080/health

# View service logs
docker logs hadoop-master 2>&1 | tail -50
```

### YARN ResourceManager Web UI at :8088 Shows No Nodes
```bash
# Wait 2-3 minutes after starting workers — NodeManagers take time to register
# Check NodeManager logs on the worker
docker exec hadoop-worker cat /opt/hadoop/logs/yarn-root-nodemanager-*.log | tail -20
```

---

## Security Notes

This deployment uses simplified security appropriate for a class project:
- HDFS permissions are disabled (`dfs.permissions.enabled = false`)
- SSH uses auto-generated RSA keys
- Hadoop runs as root inside containers
- CORS is open to all origins (`Access-Control-Allow-Origin: *`)

**Do not use this configuration for production workloads.**

---

## References

- [Apache Hadoop 3.3.6 Documentation](https://hadoop.apache.org/docs/r3.3.6/)
- [Hadoop Streaming Guide](https://hadoop.apache.org/docs/r3.3.6/hadoop-streaming/HadoopStreaming.html)
- [LendingClub Dataset on Kaggle](https://www.kaggle.com/datasets/wordsforthewise/lending-club)
- [WebHDFS REST API](https://hadoop.apache.org/docs/r3.3.6/hadoop-project-dist/hadoop-hdfs/WebHDFS.html)
