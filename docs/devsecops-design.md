# Rancangan DevSecOps Platform Berbasis Kubernetes

## Executive Summary

Dokumen ini menjelaskan rancangan teknis untuk mentransformasi proses delivery aplikasi dari pendekatan manual berbasis VM menjadi platform DevSecOps berbasis Kubernetes yang terstandar, aman, dan dapat ditelusuri. Rancangan dirancang untuk dioperasikan oleh tim kecil dengan pendekatan bertahap (phased migration) untuk meminimalkan risiko.

---

## 1. Kondisi Existing & Analisis Masalah

### Gambaran Umum

Saat ini, proses delivery aplikasi di perusahaan masih sangat bergantung pada individu tertentu yang memiliki akses dan pengetahuan tentang cara deploy ke server. Ketika orang tersebut tidak tersedia — sakit, cuti, atau resign — proses rilis terhambat. Deployment dilakukan secara manual melalui SSH, menjalankan script lokal, dan restart service satu per satu. Tidak ada catatan formal tentang siapa melakukan apa, kapan, dan versi mana yang sedang berjalan di production.

Kondisi ini menciptakan beberapa masalah fundamental yang saling terkait:

### Kondisi Saat Ini
| Area | Kondisi | Risiko |
|------|---------|--------|
| Deployment | Manual/semi-manual via SSH ke server | Human error, tidak reproducible |
| CI/CD | Belum ada pipeline standar | Inkonsistensi antar rilis |
| Security | Kontrol pre-release minim | Vulnerability lolos ke production |
| Artifact | Tidak terpusat | Tidak ada versioning yang jelas |
| Config/Secret | Tersebar di server | Kebocoran credential, drift konfigurasi |
| Monitoring | Akses manual ke server | Lambat troubleshooting, blind spot |
| Environment | DEV/PROD tanpa governance | Konfigurasi drift, rilis tidak terkontrol |

### Root Cause
- Tidak ada **separation of concerns** antara development dan operations
- Tidak ada **single source of truth** untuk konfigurasi dan state deployment
- Tidak ada **automated gate** sebelum kode masuk production
- Knowledge terpusat pada individu (single point of failure)

---

## 2. Target Architecture

### Perubahan Fundamental

Dengan arsitektur baru ini, proses delivery berubah secara fundamental:

**Sebelum (Manual/VM-based):**
- Developer SSH ke server → copy file → edit config → restart service → harap tidak ada error
- Tidak ada jejak audit siapa mengubah apa
- Jika gagal, rollback manual (jika ingat state sebelumnya)
- Monitoring hanya bisa dilakukan dengan SSH ke server dan baca log file

**Sesudah (DevSecOps/Kubernetes):**
- Developer cukup `git push` → pipeline otomatis berjalan → security scan → image ter-build → ArgoCD deploy ke Kubernetes → health check otomatis
- Setiap perubahan terekam di Git history (siapa, kapan, apa yang berubah)
- Rollback 1 klik via ArgoCD atau otomatis jika pod crash
- Monitoring via dashboard (Grafana) tanpa perlu akses server sama sekali

Perubahan ini bukan hanya soal tools — ini mengubah **model mental** tim. Dari "saya deploy manual dan bertanggung jawab penuh atas server" menjadi "saya deklarasikan state yang diinginkan di Git, dan platform yang memastikan state tersebut tercapai."

### 2.1 Arsitektur High-Level

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            DEVELOPER WORKFLOW                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  Developer → Git Push → Jenkins Pipeline → Container Registry (Harbor)     │
│                              │                                                │
│                    ┌─────────┴──────────┐                                    │
│                    │   Security Gates    │                                    │
│                    │  - SAST (Semgrep)   │                                    │
│                    │  - Image Scan       │                                    │
│                    │    (Trivy)          │                                    │
│                    │  - Secret Detection │                                    │
│                    └─────────┬──────────┘                                    │
│                              │                                                │
│                              ▼                                                │
│                    Helm Chart + Values                                        │
│                    (versioned in Git)                                         │
│                              │                                                │
└──────────────────────────────┼──────────────────────────────────────────────┘
                               │
┌──────────────────────────────┼──────────────────────────────────────────────┐
│                     GITOPS DEPLOYMENT                                         │
├──────────────────────────────┼──────────────────────────────────────────────┤
│                              ▼                                                │
│                     ArgoCD (GitOps)                                           │
│                    ┌─────────┴──────────┐                                    │
│                    │                    │                                     │
│                    ▼                    ▼                                     │
│            ┌──────────────┐   ┌──────────────┐                               │
│            │  K8s Cluster │   │  K8s Cluster │                               │
│            │     DEV      │   │     PROD     │                               │
│            │              │   │              │                               │
│            │ ┌──────────┐ │   │ ┌──────────┐ │                               │
│            │ │Namespace │ │   │ │Namespace │ │                               │
│            │ │ app-dev  │ │   │ │ app-prod │ │                               │
│            │ └──────────┘ │   │ └──────────┘ │                               │
│            └──────────────┘   └──────────────┘                               │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘
                               │
┌──────────────────────────────┼──────────────────────────────────────────────┐
│                    OBSERVABILITY STACK                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │ Prometheus │  │   Grafana  │  │    Loki    │  │ AlertMgr   │            │
│  │  (Metrics) │  │ (Dashboard)│  │  (Logging) │  │  (Alert)   │            │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘            │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────────┐
│                    EXTERNAL SERVICES (Di luar K8s)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌────────────┐  ┌────────────┐  ┌────────────┐                             │
│  │  Database  │  │   Vault    │  │  Jenkins   │                             │
│  │ (Existing) │  │ (Secrets)  │  │  (CI/CD)   │                             │
│  └────────────┘  └────────────┘  └────────────┘                             │
└───────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Keputusan Arsitektur

Setiap keputusan arsitektur diambil dengan mempertimbangkan tiga faktor utama: (1) kemampuan tim kecil untuk mengoperasikan, (2) risiko terhadap business continuity, dan (3) kemudahan evolusi di masa depan.

| Keputusan | Pilihan | Alasan |
|-----------|---------|--------|
| Cluster topology | Single cluster, namespace-based separation | Tim kecil, kompleksitas rendah, biaya efisien |
| Deployment model | GitOps via ArgoCD | Single source of truth, audit trail, self-healing |
| Database | Tetap di luar K8s | Sesuai constraint, stateful workload lebih stabil di VM |
| Secret management | HashiCorp Vault + External Secrets Operator | Centralized, auditable, rotasi otomatis |
| Ingress | NGINX Ingress Controller | Mature, well-documented, fitur cukup |
| Container runtime | containerd | Default K8s, lightweight |

**Mengapa single cluster?** Multi-cluster memberikan isolasi lebih baik antara DEV dan PROD, namun membutuhkan federation tooling, network mesh, dan effort operasional yang tinggi. Untuk tim 3-5 orang, overhead tersebut tidak sebanding dengan benefitnya. Isolasi cukup dicapai melalui namespace + NetworkPolicy + RBAC. Keputusan ini bisa di-revisit ketika tim berkembang atau ada compliance requirement yang memaksa separasi fisik.

**Mengapa database tetap di VM?** Menjalankan stateful workload (database) di Kubernetes membutuhkan penanganan khusus — persistent volume, backup strategy, replication — yang menambah kompleksitas signifikan. Database existing sudah stabil di VM dan sudah memiliki prosedur backup tersendiri. Memindahkannya ke K8s di fase awal menambah risiko tanpa memberikan benefit yang jelas. Koneksi dari pod ke database VM dilakukan via internal network (same VLAN).

### 2.3 Batasan Desain

- **Tidak dalam scope**: Refactoring aplikasi ke microservices
- **Asumsi**: Aplikasi sudah bisa di-containerize (minimal Dockerfile tersedia)
- **Database**: Tetap di VM existing, diakses via internal network
- **Cluster**: Minimum 3 worker nodes untuk HA
- **Network**: Cluster dan VM database dalam network yang sama (atau VPN)

### 2.4 Fase Implementasi

Migrasi dilakukan secara bertahap untuk meminimalkan risiko dan memastikan setiap fase stabil sebelum melanjutkan ke fase berikutnya. Pendekatan ini juga memungkinkan tim belajar dan beradaptasi secara gradual — tidak ada "big bang migration" yang memaksa semua berubah sekaligus.

| Fase | Durasi | Scope | Prioritas |
|------|--------|-------|-----------|
| **Fase 1** | 2-4 minggu | Setup K8s cluster, CI/CD pipeline, container registry | Tinggi |
| **Fase 2** | 2-3 minggu | GitOps (ArgoCD), Helm charts, secret management | Tinggi |
| **Fase 3** | 2-3 minggu | Observability stack, alerting | Medium |
| **Fase 4** | 1-2 minggu | Security gates, compliance automation | Medium |
| **Fase 5** | Ongoing | Migrasi aplikasi satu per satu | Bertahap |

**Alasan prioritas**: Fase 1-2 fokus membangun fondasi delivery yang aman. Fase 3-4 memperkuat operational visibility. Migrasi aplikasi dilakukan bertahap untuk minimize risk.

---

## 3. DevSecOps Toolchain

### Prinsip Pemilihan Tools

Pemilihan tools tidak dilakukan berdasarkan popularitas atau kelengkapan fitur semata, tetapi berdasarkan tiga prinsip:

1. **Fit with team capability** — Tools harus bisa dioperasikan oleh tim kecil (3-5 orang) tanpa dedicated specialist per tool.
2. **Minimal operational overhead** — Preferensi pada tools yang stateless (jalan di CI lalu selesai) atau yang self-managed (operator-based di K8s).
3. **Open-source first** — Menghindari vendor lock-in dan menekan biaya. Commercial tools hanya dipilih jika open-source alternative tidak memadai.

Tidak semua tools harus di-adopt sekaligus. Fase 1-2 fokus pada delivery pipeline (Jenkins + Harbor + ArgoCD). Observability dan security hardening menyusul setelah fondasi stabil.

### 3.1 Toolchain Selection

| Kategori | Tool | Alasan Pemilihan |
|----------|------|------------------|
| **Source Control** | Git Server (Gitea/Bitbucket) | Lightweight, self-hosted, on-premise control |
| **CI/CD** | Jenkins (Declarative Pipeline) | Mature, extensible, self-hosted, Jenkinsfile as code |
| **Container Registry** | Harbor | Enterprise features (vulnerability scan, replication, RBAC), on-premise |
| **Container Orchestration** | Kubernetes (kubeadm/RKE2) | Industry standard, extensible, large ecosystem |
| **GitOps** | ArgoCD | Declarative, auto-sync, rollback, multi-cluster support |
| **Helm** | Helm 3 | Templating, versioning, rollback native |
| **Secret Management** | HashiCorp Vault | Dynamic secrets, rotation, audit log, K8s native auth |
| **SAST** | Semgrep | Fast, low false-positive, custom rules, free tier |
| **Container Scanning** | Trivy | Comprehensive (OS + library), fast, CI-friendly |
| **Secret Detection** | GitLeaks | Pre-commit & CI integration, configurable rules |
| **Monitoring** | Prometheus + Grafana | De facto standard, PromQL powerful, rich dashboards |
| **Logging** | Loki + Promtail | Lightweight, label-based, integrates with Grafana |
| **Alerting** | Alertmanager | Native Prometheus integration, routing, silencing |
| **Ingress** | NGINX Ingress Controller | Stable, well-documented, SSL termination |
| **Certificate** | cert-manager | Automated TLS certificate lifecycle |

### 3.2 Alasan Tidak Memilih AlternatifP

| Alternatif | Alasan Tidak Dipilih |
|------------|---------------------|
| GitLab CI | Membutuhkan GitLab sebagai SCM (lock-in), overhead license GitLab EE |
| Flux CD | ArgoCD memiliki UI yang membantu tim kecil untuk visibility |
| ELK Stack | Resource-heavy (Elasticsearch), Loki lebih ringan untuk skala ini |
| SonarQube | Membutuhkan server dedicated (PostgreSQL + JVM + 4GB RAM). Untuk security scanning, Semgrep sudah cukup. SonarQube bisa ditambahkan di fase berikutnya jika butuh code quality metrics (duplikasi, coverage, complexity) |
| OWASP ZAP (DAST) | DAST memerlukan running application di CI environment, menambah 15-60 menit ke pipeline, dan setup-nya complex (spin up app + dependencies). SAST + image scan sudah cover mayoritas attack surface di fase awal |
| Ansible Tower | Terlalu complex untuk deployment K8s-native, GitOps lebih fit |
| AWS/GCP managed services | Constraint on-premise, vendor lock-in |

### 3.3 Integration Map

```
Developer → Git (push) → Jenkins Pipeline
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
                    ▼               ▼               ▼
              Semgrep (SAST)   Build Image    GitLeaks
                    │               │               │
                    └───────────────┼───────────────┘
                                    │
                                    ▼
                         Trivy (Image Scan)
                                    │
                                    ▼
                         Harbor (Push Image)
                                    │
                                    ▼
                    Update Helm Values (Git commit)
                                    │
                                    ▼
                         ArgoCD (Sync to K8s)
                                    │
                          ┌─────────┴─────────┐
                          ▼                   ▼
                    DEV Namespace       PROD Namespace
                                        (manual approval)
```

---

## 4. CI/CD Workflow

### Filosofi Pipeline

Pipeline dirancang dengan prinsip **"fail fast, fail early"** — jika ada masalah (build error, vulnerability, test failure), pipeline berhenti di stage tersebut dan tidak melanjutkan ke stage berikutnya. Ini memastikan bahwa artefak yang sampai ke production telah melewati semua gate tanpa exception.

Selain itu, pipeline harus **repeatable dan deterministic** — menjalankan pipeline yang sama pada commit yang sama harus menghasilkan output yang sama. Ini dicapai dengan immutable image tagging (menggunakan Git SHA, bukan `latest`) dan dependency pinning.

### 4.1 Branching Strategy

Menggunakan **Trunk-Based Development** (simplified):
- `main` → production-ready code
- `develop` → integration branch
- `feature/*` → feature development (short-lived)
- `hotfix/*` → production hotfix

**Alasan**: Sederhana, cocok untuk tim kecil, jelas mapping branch ke environment. Jenkins Multibranch Pipeline otomatis detect branch baru.

### 4.2 Pipeline Stages

```
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│  Build   │──▶│ Security │──▶│   Test   │──▶│ Package  │──▶│  Deploy  │──▶│  Verify  │
│          │   │   Scan   │   │          │   │          │   │          │   │          │
└──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘
```

#### Stage Detail:

| Stage | Aktivitas | Fail Condition |
|-------|-----------|----------------|
| **Build** | Compile, unit test, build Docker image | Build error, test failure |
| **Security Scan** | SAST (Semgrep), Secret detection (GitLeaks), Image scan (Trivy) | Critical/High vulnerability |
| **Test** | Integration test, API test (opsional) | Test failure |
| **Package** | Push image ke Harbor, tag dengan version | Push failure |
| **Deploy DEV** | ArgoCD sync ke dev namespace (auto) | Sync failure |
| **Deploy PROD** | ArgoCD sync ke prod namespace (manual approval) | Sync failure, health check fail |
| **Verify** | Smoke test, health check | Endpoint not responding |

### 4.3 Environment Promotion Strategy

Promosi artefak antar environment menggunakan prinsip **"same artifact, different config"** — Docker image yang sama di-deploy ke DEV dan PROD, yang berbeda hanya konfigurasi (values file Helm). Ini memastikan bahwa apa yang di-test di DEV benar-benar sama dengan yang di-deploy ke PROD, menghilangkan masalah "works on my machine."

```
feature/* branch  →  CI: build + test + scan (no deploy)
develop branch    →  CI: build + test + scan + deploy to DEV (auto)
main branch       →  CI: build + test + scan + manual approval + deploy to PROD
```

**Kontrol Production:**
- Merge ke `main` memerlukan Pull Request approval (minimum 1 reviewer)
- Jenkins Pipeline PROD memiliki `input` step (manual approval gate)
- ArgoCD PROD app menggunakan manual sync (tidak auto-sync)

**Mengapa tiga layer kontrol untuk PROD?** Ini defense-in-depth untuk production. PR review memastikan kode di-review oleh peer. Jenkins `input` step memastikan ada conscious decision untuk deploy. Dan ArgoCD manual sync memberikan kontrol timing — kapan exactly deployment terjadi.

### 4.4 Rollback Strategy

Rollback adalah aspek yang sering terabaikan namun kritikal. Dalam desain ini, setiap deployment memiliki jalur rollback yang jelas tanpa memerlukan intervensi manual yang kompleks.

| Skenario | Mekanisme |
|----------|-----------|
| Deployment gagal (pod crash) | K8s automatic rollback (Helm revision) |
| Bug terdeteksi post-deploy | ArgoCD rollback ke revision sebelumnya |
| Critical vulnerability | Revert Git commit → trigger pipeline ulang |
| Infrastructure issue | ArgoCD self-heal (reconcile to desired state) |
**Trade-off antara mekanisme rollback:**

- **ArgoCD rollback** (klik UI) — cepat (~30 detik), cocok untuk emergency, namun TIDAK menjalankan ulang pipeline (artinya image lama langsung di-deploy tanpa re-scan). Ini acceptable untuk situasi darurat di mana prioritasnya adalah recovery time.
- **Git revert** (revert commit → pipeline jalan ulang) — lebih lambat (~5-10 menit), namun lebih safe karena image melewati semua gate lagi (build, test, scan). Ini preferred untuk rollback non-emergency di mana ada waktu untuk validasi.
- **Kubernetes automatic rollback** — terjadi tanpa intervensi manusia saat pod baru crash (readiness probe gagal). Trade-off-nya: hanya works jika probe dikonfigurasi dengan benar; jika probe terlalu lenient, pod unhealthy bisa lolos.

Pilihan mekanisme tergantung pada **severity dan urgency** — bukan one-size-fits-all.
### 4.5 Artifact Versioning

- **Image tag**: `<app-name>:<git-short-sha>-<pipeline-id>` (immutable)
- **Helm chart version**: Semantic versioning (vX.Y.Z)
- **Tidak menggunakan `latest` tag** untuk reproducibility

---

## 5. Observability & Operation

### Mengapa Observability Adalah Prioritas

Dalam kondisi existing, satu-satunya cara mengetahui ada masalah adalah ketika user melaporkan atau ketika engineer SSH ke server dan menemukan error di log file. Ini reaktif dan lambat.

Dengan observability stack yang proper, tim bisa:
- **Mendeteksi masalah sebelum user merasakan** (alert saat error rate naik di atas threshold)
- **Mendiagnosis masalah tanpa SSH** (query log via Grafana, lihat metrics trend)
- **Memahami kapasitas** (kapan perlu scale up, resource mana yang hampir habis)

Yang penting: observability bukan berarti membuat dashboard yang cantik lalu tidak pernah dilihat. Desain ini fokus pada **actionable observability** — setiap alert punya runbook, setiap dashboard punya audience jelas, dan setup-nya realistis untuk tim kecil.

### 5.1 Three Pillars of Observability

#### Metrics (Prometheus + Grafana)
- **Infrastructure metrics**: Node CPU, memory, disk, network
- **Kubernetes metrics**: Pod status, restart count, resource utilization
- **Application metrics**: Request rate, error rate, latency (RED method)
- **Custom metrics**: Business metrics via Prometheus client library

#### Logging (Loki + Promtail)
- **Centralized logging**: Semua container logs dikumpulkan otomatis
- **Structured logging**: JSON format untuk query yang efisien
- **Retention**: 7 hari DEV, 30 hari PROD
- **Label-based query**: Filter by namespace, app, pod, severity

**Trade-off retention period**: DEV 7 hari karena log DEV hanya berguna untuk debugging aktif — setelah 7 hari, bug yang belum ditemukan sudah irrelevant (kode sudah berubah). PROD 30 hari karena post-mortem incident kadang butuh analisis log minggu lalu, dan compliance requirement umumnya meminta minimal 30 hari. Lebih lama dari 30 hari bisa dilakukan (archive ke object storage) namun menambah cost storage yang belum justified di fase awal.

#### Alerting (Alertmanager)
- **Severity levels**: Critical (PagerDuty/call), Warning (Slack), Info (email)
- **Alert routing**: Berdasarkan namespace dan severity
- **Runbook links**: Setiap alert memiliki link ke runbook

### 5.2 Dashboard Strategy

| Dashboard | Audience | Konten |
|-----------|----------|--------|
| Platform Overview | SRE/DevOps | Cluster health, resource usage, node status |
| Application Health | Dev Team | Pod status, request rate, error rate, latency |
| Deployment Tracking | All | Recent deployments, rollback events, pipeline status |
| Security Overview | Security | Vulnerability count, failed scans, policy violations |

### 5.3 Operational Procedures

#### Day-1 Operations (Setup)
- Cluster provisioning dan hardening
- Observability stack deployment
- Initial application migration

#### Day-2 Operations (Steady State)
| Task | Frequency | Automation |
|------|-----------|------------|
| Certificate renewal | Auto (cert-manager) | Full |
| Secret rotation | Scheduled (Vault) | Full |
| Image vulnerability rescan | Daily (Harbor/Trivy) | Full |
| Cluster upgrade | Quarterly | Semi-auto |
| Backup verification | Weekly | Semi-auto |
| Capacity planning | Monthly | Manual + metrics |

### 5.4 Incident Response

```
Alert Fired → Slack Notification → On-call Engineer
                                         │
                                         ▼
                              Check Grafana Dashboard
                                         │
                              ┌───────────┴───────────┐
                              │                       │
                              ▼                       ▼
                     Known Issue              Unknown Issue
                     (Runbook)               (Investigate)
                              │                       │
                              ▼                       ▼
                     Execute Fix              Logs (Loki)
                              │               Traces
                              │                       │
                              └───────────┬───────────┘
                                          │
                                          ▼
                                   Post-mortem
                                   (jika Critical)
```

### 5.5 Operasi oleh Tim Kecil

Salah satu constraint terbesar dalam desain ini adalah bahwa platform harus bisa dioperasikan oleh tim kecil (3-5 orang). Ini berarti setiap komponen yang ditambahkan harus mengurangi operational toil secara net — bukan menambahnya. Jika sebuah tool membutuhkan 1 orang dedicated untuk maintain, tool tersebut tidak layak dipilih.

Strategi konkret:

1. **GitOps reduces toil**: Deployment via Git, bukan SSH manual. Tidak ada lagi "hanya si A yang tahu cara deploy"
2. **Self-healing**: ArgoCD reconcile drift secara otomatis. Jika seseorang accidentally mengubah sesuatu via kubectl, ArgoCD akan kembalikan ke state yang benar
3. **Automated alerts**: Tidak perlu monitoring manual 24/7. Tim hanya perlu respond saat alert datang
4. **Runbooks**: Dokumentasi penanganan setiap alert — engineer baru pun bisa handle incident tanpa eskalasi ke senior
5. **Reusable templates**: Helm chart dan CI pipeline standard mengurangi custom work
6. **Progressive rollout**: Rolling update dengan maxSurge/maxUnavailable mengurangi blast radius
7. **Centralized observability**: Single pane of glass via Grafana

---

## 6. Security Design

### Pendekatan Keamanan

Keamanan dalam rancangan ini menggunakan pendekatan **shift-left** dan **defense-in-depth**:

- **Shift-left**: Deteksi vulnerability sedini mungkin dalam development lifecycle. Lebih murah memperbaiki vulnerability saat coding dibandingkan saat sudah di production (baik dari segi waktu, effort, maupun dampak).
- **Defense-in-depth**: Tidak mengandalkan satu layer keamanan saja. Jika satu layer lolos (misal: SAST tidak mendeteksi), masih ada layer berikutnya (image scan, runtime security, network policy).

Prinsipnya: security bukan gate di akhir yang menghambat rilis, tapi bagian integral dari setiap stage pipeline.

### 6.1 Shift-Left Security

| Layer | Control | Tool |
|-------|---------|------|
| Pre-commit | Secret detection | GitLeaks (pre-commit hook) |
| CI Pipeline | SAST | Semgrep |
| CI Pipeline | Dependency check | Trivy (fs mode) — opsional, dijalankan terpisah |
| CI Pipeline | Container scan | Trivy (image mode) |
| Registry | Vulnerability scan | Harbor built-in (Trivy) |
| Runtime | Pod security | Pod Security Standards (Restricted) |
| Runtime | Network policy | Kubernetes NetworkPolicy |
| Secrets | Encryption at rest | Vault + External Secrets Operator |

### 6.2 RBAC Strategy

| Role | Scope | Permissions |
|------|-------|-------------|
| Developer | App namespace (dev) | View pods, logs, exec into dev pods |
| Lead Developer | App namespace (all) | View all, approve MR |
| DevOps Engineer | Cluster-wide | Full cluster admin |
| ArgoCD | Target namespaces | Deploy, manage resources |
| CI Runner | Build namespace | Build, push images |

**Trade-off pada granularitas RBAC:**

- **Developer boleh exec ke pod DEV** — ini sengaja diizinkan karena developer butuh debugging akses saat development. Trade-off: ada risiko developer accidentally menjalankan command yang merusak pod. Mitigasi: pod DEV bisa di-recreate kapan saja (stateless), dan action tetap tercatat di audit log.
- **Developer TIDAK boleh akses PROD** — semua interaksi dengan production harus melalui pipeline dan ArgoCD. Ini menghilangkan risiko "seseorang kubectl delete di production."
- **Kenapa tidak lebih granular?** (misal: per-resource RBAC) — Untuk tim kecil, overly granular RBAC menciptakan friction yang menghambat velocity tanpa significant security gain. Cukup isolasi di level namespace (DEV vs PROD). Granularitas bisa ditingkatkan saat tim grow atau ada compliance audit.

### 6.3 Network Security
- **NetworkPolicy**: Default deny all ingress/egress per namespace
- **Whitelist**: Hanya traffic yang dibutuhkan yang diizinkan
- **Database access**: Hanya dari pod tertentu via network policy + DB credential dari Vault

---

## 7. Asumsi & Batasan

### Asumsi
1. Aplikasi existing dapat di-containerize tanpa refactoring besar
2. Tim memiliki basic knowledge Git dan Docker
3. Network antara K8s cluster dan database VM sudah tersedia
4. Resource server cukup untuk menjalankan K8s cluster (min 3 nodes)
5. Git server (Gitea/Bitbucket) digunakan sebagai SCM, Jenkins sebagai CI/CD
6. Budget tersedia untuk infrastruktur tambahan (Harbor, Vault, monitoring)

### Batasan Desain
1. Single cluster (bukan multi-cluster) untuk fase awal
2. Database TIDAK dimigrasikan ke dalam Kubernetes
3. Tidak mencakup service mesh (complexity trade-off untuk tim kecil)
4. Tidak mencakup multi-tenancy antar tim (single team assumed)
5. Disaster recovery cluster belum diimplementasikan di fase awal

### Yang Belum Diimplementasikan
1. Multi-cluster federation
2. Service mesh (Istio/Linkerd)
3. Chaos engineering
4. Full compliance automation (SOC2, ISO)
5. Blue-green deployment (menggunakan rolling update di fase awal)
6. Database migration automation

---

## 8. Risiko & Mitigasi

| Risiko | Impact | Mitigasi |
|--------|--------|----------|
| Aplikasi tidak bisa di-containerize | High | Assessment awal, fallback ke VM untuk app tertentu |
| Tim kurang skill K8s | Medium | Training, runbook, start dengan app non-critical |
| Single cluster failure | High | Regular backup etcd, DR plan untuk fase 2 |
| Secret leak | High | GitLeaks pre-commit, Vault audit log, rotation |
| Pipeline terlalu lambat | Low | Parallel stages, caching, optimized images |

---

## 9. Struktur Repository

```
devsecops-platform/
├── README.md                    # Dokumentasi utama repository
├── docs/
│   └── devsecops-design.md     # Dokumen rancangan ini
├── cicd-template/
│   ├── Jenkinsfile             # Main pipeline (Declarative Pipeline)
│   ├── Jenkinsfile.rollback    # Rollback pipeline (manual trigger)
│   └── scripts/
│       ├── docker-build.sh     # Docker build helper
│       ├── trivy-scan.sh       # Trivy scanning script
│       ├── semgrep-scan.sh     # SAST scanning script
│       └── notify.sh           # Notification helper
├── helmchart-template/
│   ├── Chart.yaml              # Helm chart metadata
│   ├── values.yaml             # Default values
│   ├── values-dev.yaml         # DEV environment overrides
│   ├── values-prod.yaml        # PROD environment overrides
│   └── templates/
│       ├── deployment.yaml     # Deployment manifest
│       ├── service.yaml        # Service manifest
│       ├── ingress.yaml        # Ingress manifest
│       ├── hpa.yaml            # HorizontalPodAutoscaler
│       ├── networkpolicy.yaml  # Network policies
│       ├── serviceaccount.yaml # ServiceAccount
│       ├── external-secret.yaml # ExternalSecret (Vault integration)
│       ├── pdb.yaml            # PodDisruptionBudget
│       └── _helpers.tpl        # Template helpers
└── argocd/
    ├── appproject.yaml         # ArgoCD project definition
    ├── app-dev.yaml            # ArgoCD Application (DEV)
    └── app-prod.yaml           # ArgoCD Application (PROD)
```
