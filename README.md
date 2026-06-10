# DevSecOps Platform — Kubernetes Delivery Foundation

## Overview

Repository ini berisi template implementasi platform DevSecOps berbasis Kubernetes untuk mentransformasi proses delivery aplikasi dari pendekatan manual berbasis VM menjadi proses yang terstandar, aman, dan dapat ditelusuri.

### Tujuan Platform
- **Standarisasi** — Satu pipeline dan satu Helm chart untuk semua aplikasi
- **Keamanan** — Security scanning terintegrasi di setiap tahap delivery (shift-left)
- **Auditabilitas** — Setiap perubahan tercatat di Git history (GitOps)
- **Operasional** — Dirancang untuk dioperasikan oleh tim kecil (3-5 orang)

### Prinsip Desain
1. **GitOps** — Git sebagai single source of truth untuk deployment state
2. **Shift-left security** — Deteksi vulnerability sedini mungkin dalam pipeline
3. **Defense in depth** — Keamanan berlapis dari code sampai runtime
4. **Pragmatic** — Tidak over-engineer; tools dipilih sesuai skala dan kemampuan tim

---

## Struktur Repository

```
devsecops-platform/
├── README.md                          # Dokumentasi ini
├── docs/
│   └── devsecops-design.md           # Dokumen rancangan teknis lengkap
├── cicd-template/
│   ├── Jenkinsfile                   # Main CI/CD pipeline (Declarative Pipeline)
│   ├── Jenkinsfile.rollback          # Rollback pipeline (manual trigger)
│   └── scripts/
│       ├── docker-build.sh           # Standardized Docker build script
│       ├── trivy-scan.sh            # Trivy vulnerability scan helper
│       ├── semgrep-scan.sh          # SAST scan helper
│       └── notify.sh               # Deployment notification (Slack/webhook)
├── helmchart-template/
│   ├── Chart.yaml                    # Helm chart metadata
│   ├── values.yaml                   # Default values (base configuration)
│   ├── values-dev.yaml              # DEV environment overrides
│   ├── values-prod.yaml             # PROD environment overrides
│   └── templates/
│       ├── _helpers.tpl             # Template helper functions
│       ├── deployment.yaml          # Kubernetes Deployment
│       ├── service.yaml             # Kubernetes Service
│       ├── ingress.yaml             # Ingress with TLS
│       ├── hpa.yaml                 # HorizontalPodAutoscaler
│       ├── networkpolicy.yaml       # Network isolation policies
│       ├── serviceaccount.yaml      # ServiceAccount (least privilege)
│       ├── external-secret.yaml     # Vault secret integration
│       └── pdb.yaml                 # PodDisruptionBudget (HA)
└── argocd/
    ├── appproject.yaml              # ArgoCD Project (RBAC boundaries)
    ├── app-dev.yaml                 # ArgoCD Application - DEV (auto-sync)
    └── app-prod.yaml                # ArgoCD Application - PROD (manual sync)
```

---

## Cara Penggunaan

### 1. CI/CD Template (Jenkins)

Copy `Jenkinsfile` ke root repository aplikasi:

```bash
cp cicd-template/Jenkinsfile my-app-repo/Jenkinsfile
```

Buat **Multibranch Pipeline** job di Jenkins yang mengarah ke repo tersebut.

**Required Jenkins Credentials** (set di Jenkins > Manage Credentials):

| Credential ID | Type | Deskripsi |
|---------------|------|-----------|
| `harbor-url` | Secret text | Harbor registry URL (e.g., `harbor.company.internal`) |
| `harbor-credentials` | Username/Password | Harbor robot account |
| `git-credentials` | Username/Password | Git PAT untuk push ke GitOps repo |
| `slack-webhook` | Secret text | Slack incoming webhook URL (opsional) |

**Required Jenkins Plugins:**
- Pipeline
- Docker Pipeline
- Credentials Binding
- Slack Notification (opsional)

### 2. Helm Chart Template

Copy `helmchart-template/` ke repository aplikasi dan sesuaikan values:

```bash
# Copy template
cp -r helmchart-template/ my-app-repo/helmchart/

# Sesuaikan konfigurasi per aplikasi
cd my-app-repo/helmchart/
vi values.yaml          # App name, port, base resources
vi values-dev.yaml      # DEV-specific (small resources, debug log)
vi values-prod.yaml     # PROD-specific (HA, autoscaling, rate-limit)
```

**Validasi sebelum deploy:**

```bash
# Lint (check syntax & best practices)
helm lint ./helmchart -f helmchart/values-dev.yaml

# Render template (lihat output YAML tanpa deploy)
helm template my-app ./helmchart -f helmchart/values-dev.yaml

# Dry-run (simulasi install ke cluster)
helm install my-app ./helmchart -f helmchart/values-dev.yaml --dry-run --debug
```

### 3. ArgoCD Configuration

Apply ArgoCD manifests ke cluster:

```bash
# Buat project (RBAC boundaries)
kubectl apply -f argocd/appproject.yaml

# Buat application (sesuaikan repoURL terlebih dahulu)
kubectl apply -f argocd/app-dev.yaml     # DEV: auto-sync enabled
kubectl apply -f argocd/app-prod.yaml    # PROD: manual sync (controlled)
```

**Catatan:** Edit `repoURL` dan `destination.namespace` di file ArgoCD sesuai environment sebelum apply.

---

## Pipeline Workflow

### Alur CI/CD End-to-End

```
┌─────────────┐     ┌──────────────┐     ┌─────────┐     ┌─────────┐
│   Build     │────▶│   Security   │────▶│  Test   │────▶│ Package │
│  (Compile + │     │  (Parallel:  │     │ (Integ  │     │ (Push   │
│  Unit Test) │     │  Semgrep +   │     │  Test)  │     │  Image) │
│             │     │  GitLeaks +  │     │         │     │         │
│             │     │  Trivy)      │     │         │     │         │
└─────────────┘     └──────────────┘     └─────────┘     └─────────┘
                                                                │
                    ┌───────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DEPLOYMENT (GitOps via ArgoCD)                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  develop branch → Auto-sync to DEV → Health check → Notify      │
│                                                                   │
│  main branch → Manual approval → Sync to PROD → Verify → Notify │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Strategi Deployment

| Environment | Trigger | Sync Mode | Rollback |
|-------------|---------|-----------|----------|
| DEV | Push ke `develop` | Auto-sync | Otomatis (ArgoCD self-heal) |
| PROD | Push ke `main` + Manual approval | Manual sync | 1-klik via ArgoCD UI |

### Strategi Rollback

| Skenario | Mekanisme | Waktu Recovery |
|----------|-----------|----------------|
| Pod crash setelah deploy | K8s automatic rollback (probe fail) | ~30 detik |
| Bug terdeteksi post-deploy | ArgoCD rollback ke revision sebelumnya | ~30 detik |
| Critical vulnerability | Git revert → pipeline ulang | ~5-10 menit |
| Manual rollback pipeline | `Jenkinsfile.rollback` (parameter: app, env, revision) | ~2 menit |

---

## Security Features

### Security Layers (Defense in Depth)

| Layer | Stage | Tool | Fungsi |
|-------|-------|------|--------|
| 1 | Pre-commit | GitLeaks | Mencegah secrets masuk ke Git |
| 2 | CI Pipeline | Semgrep | SAST — deteksi vulnerability di source code |
| 3 | CI Pipeline | Trivy (fs) | Scan vulnerable dependencies |
| 4 | CI Pipeline | Trivy (image) | Scan OS packages & libraries di container |
| 5 | Registry | Harbor | Vulnerability scan sebelum image tersedia |
| 6 | Runtime | SecurityContext | Pod non-root, read-only filesystem, drop capabilities |
| 7 | Network | NetworkPolicy | Isolasi traffic antar namespace dan pod |
| 8 | Secrets | Vault + ESO | Centralized, encrypted, auto-rotation |
| 9 | Deployment | ArgoCD | Audit trail, Git sebagai satu-satunya entry point |

### Keamanan Konfigurasi

Repository ini **TIDAK** menyimpan:
- ❌ Credential, password, atau connection string
- ❌ API keys atau tokens
- ❌ Private keys atau certificates
- ❌ Kubeconfig files

Semua konfigurasi sensitif menggunakan:
- ✅ **Jenkins Credentials Store** (masked & protected) untuk pipeline
- ✅ **HashiCorp Vault** + External Secrets Operator untuk runtime
- ✅ **Placeholder values** dalam template (`${VARIABLE_NAME}`, `<CHANGE_ME>`)

---

## Asumsi & Batasan

### Asumsi
1. Aplikasi existing dapat di-containerize (Dockerfile tersedia atau bisa dibuat)
2. Jenkins digunakan sebagai CI/CD platform (self-hosted, Git-agnostic)
3. Git server (Gitea/Bitbucket/GitHub) sudah tersedia sebagai SCM
4. Tim memiliki basic knowledge Git dan Docker
5. Infrastructure (K8s cluster, Harbor, Vault) sudah di-provisioning
6. Network connectivity antara K8s cluster dan database VM tersedia

### Batasan Desain
1. **Single cluster** dengan namespace-based separation (trade-off: overhead multi-cluster tidak sebanding untuk tim kecil)
2. **Database tetap di VM** (stateful workload lebih stabil di luar K8s, koneksi via internal network)
3. **Tidak mencakup service mesh** (Istio/Linkerd overkill untuk <10 services)
4. **Rolling update strategy** (blue-green membutuhkan 2x resource yang belum justified)

### Bagian yang Belum Diimplementasikan (Roadmap)
1. Multi-cluster deployment configuration
2. Service mesh (Istio/Linkerd) integration
3. Chaos engineering (Litmus/Chaos Monkey)
4. Compliance automation (SOC2, ISO 27001)
5. Database migration automation (Flyway/Liquibase)
6. Observability stack Helm charts (Prometheus, Grafana, Loki)
7. Vault configuration, policies, dan PKI setup
8. Infrastructure as Code (Terraform) untuk cluster provisioning
9. DAST scanning (OWASP ZAP) integration

---

## Teknologi & Toolchain

| Kategori | Tool | Alasan Pemilihan |
|----------|------|------------------|
| SCM | Git (Gitea / Bitbucket / GitHub) | Self-hosted, on-premise control |
| CI/CD | Jenkins (Declarative Pipeline) | Git-agnostic, self-hosted, extensible |
| Container Registry | Harbor | Enterprise security, RBAC, vulnerability scan |
| Orchestration | Kubernetes | Industry standard, self-healing, auto-scaling |
| GitOps | ArgoCD | UI dashboard, self-heal, rollback, audit trail |
| Packaging | Helm 3 | Templating, multi-environment, rollback native |
| SAST | Semgrep | Stateless, fast, low false-positive |
| Image Scanning | Trivy | Comprehensive, CI-friendly, free |
| Secret Detection | GitLeaks | Pre-commit + CI integration |
| Secret Management | HashiCorp Vault + ESO | Dynamic secrets, rotation, audit log |
| Monitoring | Prometheus + Grafana | De facto K8s standard, PromQL |
| Logging | Loki + Promtail | Lightweight, native Grafana integration |
| Alerting | Alertmanager | Routing, grouping, silencing |
| Ingress | NGINX Ingress Controller | Stable, well-documented, TLS termination |
| TLS | cert-manager | Automated certificate lifecycle |

---

## Dokumen Terkait

- [Rancangan DevSecOps (Detail)](docs/devsecops-design.md) — Dokumen teknis lengkap: arsitektur, toolchain rationale, CI/CD workflow, observability, security design, asumsi & batasan, risiko & mitigasi.
