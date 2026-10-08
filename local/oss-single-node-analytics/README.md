# Starting Analytics on a Single-Node ClickHouse OSS

[English](#english) | [한국어](#한국어)

---

## English

> **Migrated, not verified.** Moved on 2026-10-06 from the author's notes site (clickhouse.kr), as written there. The steps and numbers have not been re-run in this repository. The English text is an LLM-assisted translation of the Korean original.

### Introduction

There is a preconception that "building a data analytics system requires a complex cluster and a huge infrastructure investment." Developers new to ClickHouse in particular are often overwhelmed by terms in the official documentation such as cluster configuration, replication and sharding.

Surprisingly, though, ClickHouse delivers outstanding performance even on a single server. In practice, a single node can process millions of events per second and aggregate billions of rows within seconds. In CloudQuery's case, a single ClickHouse node processed 65 billion rows (about 14 TiB) at 4 million rows per second.

This post covers how to solve real analytics problems with ClickHouse OSS on a single node, and in which cases ClickHouse Cloud becomes a good option.

### Why ClickHouse?

Small startups mostly face the following situations.

- **Limited resources**: The people and budget available for infrastructure management are limited. There is often no dedicated DevOps team, and developers have to manage infrastructure as well.
- **Need for fast validation**: They must experiment and pivot quickly to find product-market fit. There is no time to spend on building complex infrastructure.
- **Uncertain data volume**: Data is small at first but can grow rapidly. They need a solution that is scalable yet requires little initial investment.
- **Cost sensitivity**: Paying millions of won per month for a data warehouse is hard. Pay-as-you-go costs of Snowflake or BigQuery often exceed expectations.

#### Surprising single-node performance

A single ClickHouse node is much more powerful than you might expect.

**Near-linear vertical scaling**: ClickHouse performance improves almost linearly as you add CPU cores and memory. One 32-core server can be easier to manage and perform better than four 8-core clusters.

**Efficient compression**: Columnar storage and compression algorithms shrink hundreds of GB of raw data to tens of GB. Compression ratios of 10:1 to 20:1 are typical.

**Scale in real cases**:

- Craigslist analyzes its entire access log with a single-node ClickHouse to implement real-time rate limiting. Complex aggregation queries finish within 100 ms.
- A SaaS company processes 1 billion events per day on a single node, and saved more than 30% in cost by migrating from Postgres.
- ServiceNow handles mobile analytics with a single ClickHouse instance, removing 30 pre-aggregated tables and enabling flexible real-time analytics.

#### When a single node is enough

Starting with a single node is reasonable if the following conditions apply.

- **Data volume**: No more than 100 million events per day, or a total of a few TB or less
- **Query pattern**: Mostly time-series aggregation and filtering rather than complex joins
- **Availability requirement**: Availability of 99.9% or lower is sufficient (analytics workloads that are not mission-critical)
- **Team size**: Developers manage it directly, without dedicated DevOps staff

These conditions actually apply to many startups and small and medium-sized businesses. If the use case grows later, ClickHouse can scale out horizontally or migrate to Cloud, so a single node is a suitable place to start.

### Small-scale analytics use cases

#### 1. Product analytics

**Scenario**: A startup running a SaaS product wants to analyze user behavior to find directions for improving the product.

**Existing problems**:

- SaaS solutions such as Mixpanel and Amplitude charge by MAU (monthly active users), so cost rises sharply as you grow.
- Google Analytics is free but limited for custom event analysis.
- Storing events in PostgreSQL makes queries slower over time and index management complicated.

**Expected benefits of a single-node ClickHouse**:

- Aggregate hundreds of millions of events within seconds
- Freely add custom events and attributes
- More than 90% savings compared with the cost of external services

#### 2. Application log analytics

**Scenario**: A startup using a microservice architecture wants to centralize the logs of many services so it can identify problems quickly.

**Existing problems**:

- Elasticsearch uses a lot of memory and cluster management is complex.
- Splunk license costs are very high.
- CloudWatch and Stackdriver have limited query capabilities, and cost increases for large-volume searches.

**Expected benefits of a single-node ClickHouse:**

Store all application logs in a structured form in ClickHouse. Log collectors such as Fluentd, Vector and Logstash can load them in real time.

- Ingest hundreds of thousands of logs per second in real time
- Supports both full-text search and structured queries
- Automatic TTL deletes old logs, automating storage management

#### 3. IoT sensor data monitoring

**Scenario**: A startup managing IoT devices collects and monitors real-time data from thousands of sensors.

**Existing problems**:

- Time-series databases (InfluxDB, TimescaleDB) have their own query languages or limited SQL support
- Query performance degrades as data grows
- Complex aggregations and joins are difficult

**Expected benefits of a single-node ClickHouse**:

- Process millisecond-level sensor data in real time
- Run complex time-series analysis with standard SQL
- Keep data for long periods and analyze trends

#### 4. A/B testing and experimentation platforms

**Scenario**: A product team runs A/B tests frequently to measure the effect of various features.

**Expected benefits of a single-node ClickHouse**:

- Monitor experiment results in real time
- Enable complex segment analysis
- Compare with past experiment data

### Limits of a single node and when to move to a cluster

#### Limits of a single node

Consider moving to a cluster when the following situations occur.

- **Running out of storage capacity**: When a single server's disk reaches its limit. This generally becomes a problem at tens of TB or more.
- **Query concurrency problems**: When more concurrent queries exhaust CPU or memory. Limits are generally felt at several hundred queries per second or more.
- **High-availability requirements**: When the workload has grown into a mission-critical one where downtime is not allowed.
- **Geographic distribution**: When data must be accessed with low latency from multiple regions.

#### Gradual transition strategy

ClickHouse makes it relatively easy to move from a single node to a cluster.

1. **Start with replication**: Replicate the same data to several nodes to gain high availability
2. **Add sharding**: Distribute data across nodes to scale capacity and performance
3. **Consider ClickHouse Cloud**: When the burden of managing it yourself grows, move to a managed service

### ClickHouse Cloud: why it can be a better choice

Starting with single-node ClickHouse OSS is a great choice, but in certain situations ClickHouse Cloud can offer better value for cost. That is because you can use the following distinctive advantages without the burden of managing infrastructure yourself.

#### 1. Automatic Idling: billing stops when not in use

The most powerful cost-saving feature of ClickHouse Cloud is **automatic idling**.

**How it works**: If a service receives no queries for a set time, compute resources are paused automatically. In this state no compute cost is incurred and you pay only for storage. When a new query arrives, the service restarts automatically.

**Actual cost effect**:

- A development/test environment stops automatically outside business hours (9-6), so compute cost is zero for 75% of the day
- Analytics dashboards unused on weekends and at night are billed only for actual use
- Compute cost savings of 70-80% on a monthly average are possible

**Suitable use cases**:

- Internal analytics tools used only during business hours
- Development and staging environments
- Batch analytics jobs run periodically
- Data archives queried intermittently

**Advantage over OSS**: In a self-managed environment you have to switch servers off and on manually, and additional configuration is needed for data persistence and fast restarts. ClickHouse Cloud automates all of this.

#### 2. Elastic Scaling: automatic scaling with the workload

ClickHouse Cloud supports both vertical and horizontal scaling and adjusts resources automatically.

**Automatic vertical scaling**:

- When CPU utilization exceeds 50-75%, CPU and memory automatically double
- When utilization falls to half of the threshold or less, they are automatically halved
- Set minimum/maximum memory ranges for predictable cost management

**Horizontal scaling** (Scale/Enterprise plans):

- Adjust the number of replicas dynamically through the API
- Add replicas during bulk data loading to speed up processing
- Scale automatically during hours with many concurrent queries

**Make-Before-Break architecture**: ClickHouse Cloud uses a distinctive scaling approach. It prepares the new node first and removes the old node once the new one is ready. This means query performance is not affected during scaling.

**Real scenario**:

```text
평소: 8GB RAM, 2 vCPU (기본)
월말 리포트 시즌: 자동으로 32GB RAM, 8 vCPU로 확장
마케팅 캠페인 중: Replica 3대로 증가하여 동시 쿼리 처리
```

(Translation of the block above: Normally: 8GB RAM, 2 vCPU (default). Month-end reporting season: automatically scales to 32GB RAM, 8 vCPU. During a marketing campaign: increases to 3 replicas to handle concurrent queries.)

**Cost optimization**: Resources are used only when needed, so there is no need to over-provision for the maximum workload. Billing follows actual usage, so average savings of 40-60% are possible.

#### 3. Model Context Protocol (MCP) support: native integration with AI

ClickHouse Cloud has officially supported **MCP (Model Context Protocol)** since 2024, greatly simplifying integration with AI agents.

**Remote MCP Server (Private Preview)**:

- A managed MCP server built into the ClickHouse Cloud service
- OAuth-based authentication ensures security
- Restricted to read-only for safe data access
- No separate infrastructure to build or manage

**Supported AI tools**:

- Claude (Anthropic) - analyze data by conversing directly
- ChatGPT - run queries in natural language
- Cursor, Windsurf - use data context inside the IDE
- Custom AI agents and agentic applications

**Real usage example**:

```text
사용자: "지난 주 가장 많이 팔린 제품 상위 10개를 보여줘"

AI Agent: ClickHouse MCP를 통해 자동으로:
1. 적절한 테이블 스키마 확인
2. SQL 쿼리 생성 및 실행
3. 결과를 자연어로 설명하고 차트로 시각화
```

(Translation of the block above: User: "Show me the top 10 best-selling products last week". AI Agent, automatically via ClickHouse MCP: 1. checks the appropriate table schema, 2. generates and runs the SQL query, 3. explains the result in natural language and visualizes it as a chart.)

- **Ask AI Agent (Beta)**: An AI assistant built into the ClickHouse Cloud console that converts natural-language questions into SQL and explains the results. Business users who do not know SQL can access data directly.
- **Agent-Facing Analytics**: ClickHouse is preparing for a future in which AI agents, not only humans, are the main users. Agents run queries at machine speed, keep context, and generate insights semi-automatically.
- **Advantage over OSS**: To use MCP with OSS you have to install and manage a separate mcp-clickhouse server and configure authentication and security yourself. ClickHouse Cloud provides this fully managed.

#### 4. Separated storage and compute architecture

ClickHouse Cloud is based on the **SharedMergeTree** engine, which uses object storage (S3/GCS/Azure Blob) as the backend.

**Advantages**:

- **Independent scaling**: Storage and compute can be scaled independently
- **Cost efficiency**: Storage is very cheap ($25.30 per TB per month)
- **Unlimited snapshots**: Backup and recovery are cheap and fast
- **Zero-downtime scaling**: Change only compute without touching storage

**Limits of OSS**: Traditional MergeTree couples storage and compute, so when the disk fills up the whole system must be scaled.

#### 5. Zero operational burden

**Automated operations**:

- Automatic backup and recovery
- Automatic patches and security updates
- Automatic performance tuning and optimization
- 24/7 monitoring and alerts

**Cost transparency**:

- Detailed usage tracking through the Billing API
- Integration with FinOps tools such as Vantage
- Alerts for unexpected cost increases
- Cost control by setting an upper limit on compute autoscaling

**Work required when operating OSS**:

- Applying security patches regularly
- Building and managing a monitoring system
- Establishing and testing a backup strategy
- Performance tuning and troubleshooting
- Managing and extending disk space

#### 6. Actual cost comparison

**Scenario: analytics platform of a small startup**

Conditions:

- 100 million events collected per day on average
- About 200GB of storage after compression
- Used mainly during business hours (9-6)
- Almost unused on weekends

**ClickHouse OSS (self-managed)**:

- AWS EC2 r6g.2xlarge (8 vCPU, 64GB RAM): $0.403/hour
- EBS storage 300GB: $30/month
- Total monthly cost: $0.403 × 24 × 30 + $30 = **$320/month**
- Additional cost: DevOps time (monitoring, backups, patches and so on)

**ClickHouse Cloud (Development Tier)**:

- Storage 200GB: $5.06/month
- Compute (using idling): 30% utilization on average
    - $0.22/hour × 24 hours × 30 days × 0.3 = $47.52/month
- Total monthly cost: **about $53/month**
- Additional benefits: operational automation, MCP support, automatic scaling

**Cost savings**: About **83% savings** plus saved operations time

#### 7. When should you choose ClickHouse Cloud?

ClickHouse Cloud is more suitable in the following cases.

**From a cost perspective**:

- When the workload is intermittent or unpredictable (using idling)
- When you grow quickly and need to scale often
- When DevOps resources are limited (lower operating cost)

**From a feature perspective**:

- When you want to offer a natural-language interface integrated with AI/LLMs
- When rapid prototyping and release speed matter
- When you need automated backup, monitoring and scaling

**From an organizational perspective**:

- When you want to focus on product development rather than data infrastructure
- When you want to leave security and compliance to a specialist team
- When you plan global expansion

### Conclusion: choosing for your situation

**ClickHouse OSS on a single node is suitable when**:

- You need complete control and customization
- The workload runs continuously 24/7
- You already have DevOps capability and infrastructure
- You have special network or security requirements

**ClickHouse Cloud is suitable when**:

- You want a quick start and simpler operations
- The workload fluctuates a lot (using idling/scaling)
- You want to integrate AI/natural-language interfaces
- DevOps resources are limited

In many cases, using ClickHouse Cloud's idling and autoscaling is **actually cheaper** than managing it yourself and much more convenient. Especially for small startups, investing the time spent on infrastructure management in product development can create greater value.

Whether you start with OSS or choose Cloud, what matters is to **start fast and validate the value of data-driven decision-making**. ClickHouse offers outstanding performance and flexibility on both paths.

### Getting started with ClickHouse

#### Getting started with OSS

The ClickHouse OSS binary can be downloaded from the official site, and for those who want to test easily on Docker, the following scripts were written.

[clickhouse-hols/local/oss-docker](https://github.com/litkhai/clickhouse-hols/tree/main/local/oss-docker)

#### Getting started with Cloud

Getting started with Cloud is covered in another post.

Getting started with ClickHouse Cloud

#### References

- [ClickHouse Official Documentation](https://clickhouse.com/docs)
- [ClickHouse Docker Hub](https://hub.docker.com/r/clickhouse/clickhouse-server)
- [ClickHouse Examples Repository](https://github.com/ClickHouse/examples)
- [CloudQuery - Six Months with ClickHouse](https://www.cloudquery.io/blog/six-months-with-clickhouse-at-cloudquery)
- [ClickHouse Community: Creative Use Cases](https://clickhouse.com/docs/community-wisdom/creative-use-cases)
- [ClickHouse Cloud Pricing](https://clickhouse.com/pricing)
- [ClickHouse Cloud Automatic Scaling](https://clickhouse.com/docs/manage/scaling)
- [ClickHouse MCP Integration](https://clickhouse.com/blog/clickhouse-cloud-joins-aws-ai-agents-and-tools-mcp)
- [Agent-Facing Analytics](https://clickhouse.com/blog/agent-facing-analytics)

---

## 한국어

> **이관본, 미검증.** 2026-10-06 작성자의 노트 사이트(clickhouse.kr)에서 원문 그대로 옮겼습니다. 이 저장소에서 단계와 수치를 다시 실행하지 않았습니다. 영어본은 한국어 원문을 LLM 도움으로 번역한 것입니다.

### 들어가며

"데이터 분석 시스템을 구축하려면 복잡한 클러스터와 막대한 인프라 투자가 필요하다"는 선입견이 있습니다. 특히 ClickHouse를 처음 접하는 개발자들은 공식 문서에서 다루는 클러스터 구성, Replication, Sharding 같은 용어들에 압도되곤 합니다.

하지만 놀랍게도 ClickHouse는 단 한 대의 서버로도 엄청난 성능을 발휘합니다. 실제로 단일 노드에서 초당 수백만 건의 이벤트를 처리하고, 수십억 건의 데이터를 몇 초 안에 집계할 수 있습니다. CloudQuery의 사례에서는 단일 ClickHouse 노드가 650억 개의 행(약 14TiB)을 초당 400만 행의 속도로 처리했습니다.

이 글에서는 ClickHouse OSS를 단일 노드로 구성하여 실제 분석 문제를 해결하는 방법을 다루고자 합니다. 그리고 어떤 경우 ClickHouse Cloud를 사용하는 것이 좋은 선택사항이 되는지 함께 다루고자 합니다.

### 왜 ClickHouse인가?

소규모 스타트업은 대부분 다음과 같은 상황에 직면합니다.

- **제한된 리소스**: 인프라 관리에 투입할 수 있는 인력과 예산이 제한적입니다. DevOps 전담 팀이 없는 경우가 많고, 개발자가 인프라까지 관리해야 합니다.
- **빠른 검증 필요**: 제품-시장 적합성(Product-Market Fit)을 찾기 위해 빠르게 실험하고 피봇해야 합니다. 복잡한 인프라 구축에 시간을 쏟을 여유가 없습니다.
- **불확실한 데이터 볼륨**: 초기에는 데이터가 많지 않지만, 성장하면서 급격히 증가할 수 있습니다. 확장 가능하면서도 초기 투자가 적은 솔루션이 필요합니다.
- **비용 민감성**: 매달 수백만 원의 데이터 웨어하우스 비용을 감당하기 어렵습니다. Snowflake나 BigQuery의 종량제 비용이 예상을 초과하는 경우가 빈번합니다.

#### 싱글 노드의 놀라운 성능

ClickHouse의 싱글 노드는 생각보다 훨씬 강력합니다.

**선형적 수직 확장**: ClickHouse는 CPU 코어와 메모리를 추가할수록 거의 선형적으로 성능이 향상됩니다. 32코어 서버 한 대가 8코어 클러스터 4대보다 관리가 쉽고 성능도 우수할 수 있습니다.

**효율적인 압축**: Columnar storage와 압축 알고리즘으로 수백 GB의 원본 데이터가 수십 GB로 압축됩니다. 일반적으로 10:1에서 20:1의 압축률을 보입니다.

**실제 사례의 스케일**:

- Craigslist는 단일 노드 ClickHouse로 전체 액세스 로그를 분석하여 실시간 Rate Limiting을 구현했습니다. 복잡한 집계 쿼리가 100ms 이내에 완료됩니다.
- 한 SaaS 기업은 단일 노드로 일 10억 건의 이벤트를 처리하며, Postgres에서 마이그레이션하여 30% 이상의 비용을 절감했습니다.
- ServiceNow는 모바일 애널리틱스를 단일 ClickHouse 인스턴스로 처리하며, 30개의 사전 집계 테이블을 제거하고 유연한 실시간 분석을 구현했습니다.

#### 단일 노드로 충분한 경우

다음 조건에 해당한다면 단일 노드로 시작하는 것이 합리적입니다.

- **데이터 볼륨**: 일 1억 건 이하의 이벤트, 또는 총 데이터가 수 TB 이내
- **쿼리 패턴**: 복잡한 Join보다는 시계열 집계와 필터링이 주를 이루는 경우
- **가용성 요구사항**: 99.9% 이하의 가용성으로 충분한 경우 (미션 크리티컬하지 않은 분석 워크로드)
- **팀 규모**: DevOps 전담 인력 없이 개발자가 직접 관리하는 경우

이러한 조건은 실제로 많은 스타트업과 중소기업에 해당합니다. 나중에 유즈케이스가 성장하면 ClickHouse는 수평 확장을 수행하거나 Cloud로 마이그레이션이 가능하므로, 단일 노드로 시작하기에 적합합니다.

### 소규모 분석 활용 사례

##### 1. 제품 애널리틱스 (Product Analytics)

**시나리오**: SaaS 제품을 운영하는 스타트업에서 사용자 행동을 분석하여 제품 개선 방향을 찾고자 합니다.

**기존 문제점**:

- Mixpanel, Amplitude 같은 SaaS 솔루션은 MAU(월간 활성 사용자) 기반 요금제로 성장할수록 비용이 급증합니다.
- Google Analytics는 무료이지만 커스텀 이벤트 분석에 한계가 있습니다.
- PostgreSQL에 이벤트를 저장하면 시간이 지날수록 쿼리가 느려지고, 인덱스 관리가 복잡해집니다.

**ClickHouse 싱글 노드 활용 기대 효과**:

- 수억 건의 이벤트를 수 초 내에 집계
- 사용자 정의 이벤트와 속성을 자유롭게 추가 가능
- 외부 서비스 비용 대비 90% 이상 절감

##### 2. 애플리케이션 로그 분석 (Log Analytics)

**시나리오**: 마이크로서비스 아키텍처를 사용하는 스타트업에서 여러 서비스의 로그를 중앙화하여 문제를 빠르게 파악하고자 합니다.

**기존 문제점**:

- Elasticsearch는 메모리 사용량이 크고, 클러스터 관리가 복잡합니다.
- Splunk는 라이선스 비용이 매우 높습니다.
- CloudWatch나 Stackdriver는 쿼리 기능이 제한적이고, 대용량 검색 시 비용이 증가합니다.

**ClickHouse 싱글 노드 활용 기대 효과:**

모든 애플리케이션 로그를 구조화된 형태로 ClickHouse에 저장합니다. Fluentd, Vector, Logstash 같은 로그 수집기를 사용하여 실시간으로 적재할 수 있습니다.

- 초당 수십만 건의 로그를 실시간 수집
- 전문 검색(Full-text search)과 구조화된 쿼리를 모두 지원
- 자동 TTL로 오래된 로그 삭제하여 스토리지 관리 자동화

##### 3. IoT 센서 데이터 모니터링

**시나리오**: IoT 디바이스를 관리하는 스타트업에서 수천 개의 센서로부터 실시간 데이터를 수집하고 모니터링합니다.

**기존 문제점**:

- 시계열 데이터베이스(InfluxDB, TimescaleDB)는 고유한 쿼리 언어나 제한된 SQL 지원
- 데이터가 증가하면서 쿼리 성능이 저하됨
- 복잡한 집계나 조인이 어려움

**ClickHouse 싱글 노드 활용 기대 효과**:

- 밀리초 단위의 센서 데이터를 실시간 처리
- 표준 SQL로 복잡한 시계열 분석 수행
- 장기간 데이터 보관 및 트렌드 분석 가능

##### 4. A/B 테스팅 및 실험 플랫폼

**시나리오**: 제품 팀에서 다양한 기능의 효과를 측정하기 위해 A/B 테스트를 자주 실행합니다.

**ClickHouse 싱글 노드 활용 기대 효과**:

- 실시간으로 실험 결과 모니터링
- 복잡한 세그먼트 분석 가능
- 과거 실험 데이터와 비교 분석

#### 단일 노드의 한계와 클러스터로의 전환 시점

##### 단일 노드의 한계

다음 상황이 발생하면 클러스터로의 전환을 고려해야 합니다.

- **스토리지 용량 부족**: 단일 서버의 디스크 용량이 한계에 도달했을 때. 일반적으로 수십 TB 이상에서 문제가 됩니다.
- **쿼리 동시성 문제**: 동시 쿼리가 많아지면서 CPU나 메모리가 부족해지는 경우. 일반적으로 초당 수백 개 이상의 쿼리에서 한계를 느낍니다.
- **고가용성 요구**: 다운타임이 허용되지 않는 미션 크리티컬한 워크로드로 발전한 경우.
- **지리적 분산**: 여러 지역에서 낮은 지연시간으로 데이터에 접근해야 하는 경우.

##### 점진적 전환 전략

ClickHouse는 단일 노드에서 클러스터로 비교적 쉽게 전환할 수 있습니다.

1. **Replication부터 시작**: 같은 데이터를 여러 노드에 복제하여 고가용성 확보
2. **Sharding 추가**: 데이터를 여러 노드에 분산하여 용량과 성능 확장
3. **ClickHouse Cloud 고려**: 직접 관리의 부담이 커지면 매니지드 서비스로 전환

### ClickHouse Cloud: 더 나은 선택이 될 수 있는 이유

단일 노드 ClickHouse OSS로 시작하는 것은 훌륭한 선택이지만, 특정 상황에서는 ClickHouse Cloud가 비용 대비 더 나은 이점을 제공할 수 있습니다. 직접 인프라를 관리하는 부담 없이 다음과 같은 독특한 장점들을 활용할 수 있기 때문입니다.

#### 1. Automatic Idling: 사용하지 않을 때는 과금 중단

ClickHouse Cloud의 가장 강력한 비용 절감 기능은 **자동 Idling**입니다.

**작동 원리**: 서비스에 일정 시간 동안 쿼리가 없으면 자동으로 Compute 리소스가 일시 중지됩니다. 이 상태에서는 Compute 비용이 전혀 발생하지 않으며, 스토리지 비용만 지불합니다. 새로운 쿼리가 들어오면 자동으로 재시작됩니다.

**실제 비용 효과**:

- 개발/테스트 환경에서 업무 시간(9-6시) 외에는 자동으로 중단되어 하루 중 75%의 시간 동안 Compute 비용이 0원
- 주말과 야간에 사용하지 않는 분석 대시보드는 실제 사용 시간만 과금
- 한 달 평균 70-80%의 Compute 비용 절감 가능

**적합한 사용 사례**:

- 업무 시간에만 사용하는 내부 분석 도구
- 개발 및 스테이징 환경
- 주기적으로 사용하는 배치 분석 작업
- 간헐적으로 조회하는 데이터 아카이브

**OSS 대비 장점**: 직접 관리하는 환경에서는 서버를 수동으로 껐다 켜야 하며, 데이터 영속성과 빠른 재시작을 위한 추가 설정이 필요합니다. ClickHouse Cloud는 이 모든 것을 자동화합니다.

#### 2. Elastic Scaling: 워크로드에 따른 자동 확장

ClickHouse Cloud는 수직(Vertical)과 수평(Horizontal) 확장을 모두 지원하며, 자동으로 리소스를 조정합니다.

**수직 자동 확장**:

- CPU 사용률이 50-75%를 넘으면 자동으로 CPU와 메모리가 2배로 증가
- 사용률이 임계값의 절반 이하로 떨어지면 자동으로 절반으로 축소
- 최소/최대 메모리 범위를 설정하여 예측 가능한 비용 관리

**수평 확장** (Scale/Enterprise 플랜):

- API를 통해 Replica 수를 동적으로 조정
- 대량 데이터 적재 시 Replica를 늘려 처리 속도 향상
- 동시 쿼리가 많은 시간대에 자동으로 확장

**Make-Before-Break 아키텍처**: ClickHouse Cloud는 독특한 확장 방식을 사용합니다. 새로운 노드를 먼저 준비하고, 준비가 완료되면 기존 노드를 제거합니다. 이는 확장 과정 중에도 쿼리 성능에 영향이 없음을 의미합니다.

**실제 시나리오**:

```text
평소: 8GB RAM, 2 vCPU (기본)
월말 리포트 시즌: 자동으로 32GB RAM, 8 vCPU로 확장
마케팅 캠페인 중: Replica 3대로 증가하여 동시 쿼리 처리
```

**비용 최적화**: 필요할 때만 리소스를 사용하므로, 최대 워크로드를 위해 과도하게 프로비저닝할 필요가 없습니다. 실제 사용량에 따라 과금되어 평균 40-60%의 비용 절감이 가능합니다.

#### 3. Model Context Protocol (MCP) 지원: AI와 네이티브 통합

ClickHouse Cloud는 2024년부터 **MCP (Model Context Protocol)** 를 공식 지원하며, AI 에이전트와의 통합을 크게 단순화했습니다.

**Remote MCP Server (Private Preview)**:

- ClickHouse Cloud 서비스에 내장된 관리형 MCP 서버
- OAuth 기반 인증으로 보안 보장
- Read-only로 제한하여 안전한 데이터 접근
- 별도 인프라 구축이나 관리 불필요

**지원하는 AI 도구**:

- Claude (Anthropic) - 직접 대화하며 데이터 분석
- ChatGPT - 자연어로 쿼리 실행
- Cursor, Windsurf - IDE 내에서 데이터 컨텍스트 활용
- 커스텀 AI 에이전트 및 Agentic 애플리케이션

**실제 활용 예시**:

```text
사용자: "지난 주 가장 많이 팔린 제품 상위 10개를 보여줘"

AI Agent: ClickHouse MCP를 통해 자동으로:
1. 적절한 테이블 스키마 확인
2. SQL 쿼리 생성 및 실행
3. 결과를 자연어로 설명하고 차트로 시각화
```

- **Ask AI Agent (Beta)**: ClickHouse Cloud 콘솔에 내장된 AI 어시스턴트로, 자연어 질문을 SQL로 변환하고 결과를 설명합니다. SQL을 모르는 비즈니스 사용자도 데이터에 직접 접근할 수 있게 됩니다.
- **Agent-Facing Analytics**: ClickHouse는 사람뿐만 아니라 AI 에이전트가 주요 사용자가 되는 미래를 준비하고 있습니다. 에이전트는 기계 속도로 쿼리를 실행하고, 컨텍스트를 유지하며, 반자동으로 인사이트를 생성합니다.
- **OSS 대비 장점**: OSS에서 MCP를 사용하려면 별도로 mcp-clickhouse 서버를 설치하고 관리해야 하며, 인증 및 보안 설정을 직접 구성해야 합니다. ClickHouse Cloud는 이를 완전히 관리형으로 제공합니다.

#### 4. 분리된 스토리지와 Compute 아키텍처

ClickHouse Cloud는 Object Storage (S3/GCS/Azure Blob)를 백엔드로 사용하는 **SharedMergeTree** 엔진을 기반으로 합니다.

**장점**:

- **독립적인 확장**: 스토리지와 Compute를 각각 독립적으로 확장 가능
- **비용 효율성**: 스토리지 비용이 매우 저렴 (TB당 $25.30/월)
- **무제한 스냅샷**: 백업과 복구가 저렴하고 빠름
- **Zero-downtime 확장**: 스토리지를 건드리지 않고 Compute만 변경

**OSS의 한계**: 전통적인 MergeTree는 스토리지와 Compute가 결합되어 있어, 디스크가 가득 차면 전체 시스템을 확장해야 합니다.

#### 5. 운영 부담 제로

**자동화된 운영**:

- 자동 백업 및 복구
- 자동 패치 및 보안 업데이트
- 자동 성능 튜닝 및 최적화
- 24/7 모니터링 및 알림

**비용 투명성**:

- Billing API를 통한 상세한 사용량 추적
- Vantage 같은 FinOps 도구와 통합
- 예상치 못한 비용 증가에 대한 알림
- Compute 자동 확장 상한선 설정으로 비용 제어

**OSS 운영 시 필요한 작업**:

- 정기적인 보안 패치 적용
- 모니터링 시스템 구축 및 관리
- 백업 전략 수립 및 테스트
- 성능 튜닝 및 문제 해결
- 디스크 공간 관리 및 확장

#### 6. 실제 비용 비교

**시나리오: 소규모 스타트업의 분석 플랫폼**

조건:

- 일 평균 1억 건의 이벤트 수집
- 압축 후 약 200GB 스토리지
- 업무 시간(9-6시) 동안만 주로 사용
- 주말은 거의 사용 안 함

**ClickHouse OSS (직접 관리)**:

- AWS EC2 r6g.2xlarge (8 vCPU, 64GB RAM): $0.403/시간
- EBS 스토리지 300GB: $30/월
- 매월 총 비용: $0.403 × 24 × 30 + $30 = **$320/월**
- 추가 비용: DevOps 시간 (모니터링, 백업, 패치 등)

**ClickHouse Cloud (Development Tier)**:

- 스토리지 200GB: $5.06/월
- Compute (Idling 활용): 평균 30% 사용률
    - $0.22/시간 × 24시간 × 30일 × 0.3 = $47.52/월
- 매월 총 비용: **약 $53/월**
- 추가 이점: 운영 자동화, MCP 지원, 자동 확장

**비용 절감**: 약 **83% 절감** + 운영 시간 절약

#### 7. 언제 ClickHouse Cloud를 선택해야 할까?

다음 경우에 ClickHouse Cloud가 더 적합합니다.

**비용 관점**:

- 워크로드가 간헐적이거나 예측 불가능한 경우 (Idling 활용)
- 빠르게 성장하여 자주 확장이 필요한 경우
- DevOps 리소스가 제한적인 경우 (운영 비용 절감)

**기능 관점**:

- AI/LLM과 통합하여 자연어 인터페이스를 제공하고 싶은 경우
- 빠른 프로토타이핑과 출시 속도가 중요한 경우
- 자동화된 백업, 모니터링, 확장이 필요한 경우

**조직 관점**:

- 데이터 인프라보다 제품 개발에 집중하고 싶은 경우
- 보안 및 규정 준수를 전문 팀에 맡기고 싶은 경우
- 글로벌 확장을 계획하는 경우

### 결론: 상황에 맞는 선택

**ClickHouse OSS 단일 노드는 다음 경우에 적합**:

- 완전한 제어와 커스터마이징이 필요
- 24/7 연속 실행되는 워크로드
- 이미 DevOps 역량과 인프라가 있음
- 특수한 네트워크 또는 보안 요구사항

**ClickHouse Cloud는 다음 경우에 적합**:

- 빠른 시작과 운영 단순화
- 변동이 큰 워크로드 (Idling/Scaling 활용)
- AI/자연어 인터페이스 통합
- 제한된 DevOps 리소스

많은 경우, ClickHouse Cloud의 Idling과 자동 확장을 활용하면 직접 관리하는 것보다 **실제 비용이 더 저렴**하면서도 훨씬 편리합니다. 특히 소규모 스타트업에서는 인프라 관리에 쏟는 시간을 제품 개발에 투자하는 것이 더 큰 가치를 만들어낼 수 있습니다.

OSS로 시작하든 Cloud를 선택하든, 중요한 것은 **빠르게 시작하여 데이터 기반 의사결정의 가치를 검증하는 것**입니다. ClickHouse는 두 가지 경로 모두에서 탁월한 성능과 유연성을 제공합니다.

### ClickHouse 시작하기

#### OSS 시작하기

ClickHouse OSS 바이너리는 공식 사이트에서 다운로드 받을 수 있으며, 쉽게 Docker 기반으로 테스트를 수행하고자 하는 경우를 위해 다음과 같은 스크립트를 작성하였습니다.

[clickhouse-hols/local/oss-docker](https://github.com/litkhai/clickhouse-hols/tree/main/local/oss-docker)

#### Cloud 시작하기

다른 글에서 Cloud 시작에 대해서 다루고 있습니다.

ClickHouse Cloud 시작하기

#### 참고 자료

- [ClickHouse Official Documentation](https://clickhouse.com/docs)
- [ClickHouse Docker Hub](https://hub.docker.com/r/clickhouse/clickhouse-server)
- [ClickHouse Examples Repository](https://github.com/ClickHouse/examples)
- [CloudQuery - Six Months with ClickHouse](https://www.cloudquery.io/blog/six-months-with-clickhouse-at-cloudquery)
- [ClickHouse Community: Creative Use Cases](https://clickhouse.com/docs/community-wisdom/creative-use-cases)
- [ClickHouse Cloud Pricing](https://clickhouse.com/pricing)
- [ClickHouse Cloud Automatic Scaling](https://clickhouse.com/docs/manage/scaling)
- [ClickHouse MCP Integration](https://clickhouse.com/blog/clickhouse-cloud-joins-aws-ai-agents-and-tools-mcp)
- [Agent-Facing Analytics](https://clickhouse.com/blog/agent-facing-analytics)
