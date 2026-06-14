# 🚀 retail-store-gitops — GitOps Configuration Repo

> **The GitOps configuration repository for the Zero-Touch GitOps Factory project.**
> ArgoCD watches this repo. Jenkins updates it. You never touch Kubernetes manually.

![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-orange)
![Helm](https://img.shields.io/badge/Packaging-Helm-blue)
![IaC](https://img.shields.io/badge/IaC-Terraform-purple)
![Config](https://img.shields.io/badge/Config-Ansible-red)

---

## 📋 Table of Contents

- [What is this repo?](#-what-is-this-repo)
- [Two-Repo GitOps Pattern](#-two-repo-gitops-pattern)
- [Repository Structure](#-repository-structure)
- [Helm Chart](#-helm-chart)
- [How Jenkins Updates This Repo](#-how-jenkins-updates-this-repo)
- [How ArgoCD Uses This Repo](#-how-argocd-uses-this-repo)
- [Infrastructure (Terraform)](#-infrastructure-terraform)
- [Configuration (Ansible)](#-configuration-ansible)
- [Rollback Guide](#-rollback-guide)

---

## 🎯 What is this repo?

This is the **GitOps configuration repository** — the second half of the two-repo GitOps pattern.

```
┌─────────────────────────┐      ┌──────────────────────────┐
│  retail-store-sample-app │      │   retail-store-gitops    │
│   (App Source Code)     │      │      (This Repository)         │
│                          │      │                          │
│  ├── src/                │      │  ├── helm/               │
│  ├── Dockerfiles         │      │  │   ├── Chart.yaml      │
│  ├── Jenkinsfile         │      │  │   ├── values.yaml ◄── Jenkins updates
│  └── devops/            │      │  │   └── templates/      │
│      ├── terraform/      │      │  ├── argocd-app.yaml     │
│      └── ansible/        │      │  └── devops/             │
│                          │      │      ├── terraform/      │
│  Jenkins CI watches this │      │      └── ansible/        │
│                          │      │                          │
└─────────────────────────┘      │  ArgoCD CD watches this  │
                                  └──────────────────────────┘
```

**Rule:** If it's not in this repo → it doesn't exist in the cluster.

---

## 🔄 Two-Repo GitOps Pattern

### Why not one repo?

| Problem (one repo) | Solution (two repos) |
|---|---|
| Jenkins triggers on every push | CI and CD have separate triggers |
| ArgoCD triggers on code changes | ArgoCD only reacts to config changes |
| Circular triggers (infinite loop) | No circular triggers possible |
| Mixed audit trail | Clean separation: code vs config history |
| Developer needs K8s knowledge | Devs work in Repo 1, DevOps in Repo 2 |

### How they connect

```
Repo 1 (app-source)              Repo 2 (app-config = THIS REPO)
─────────────────────            ────────────────────────────────
Developer pushes code            ArgoCD watches main branch
       ↓                                    ↑
Jenkins CI builds images                    │
       ↓                                    │
Jenkins updates values.yaml ───────────────►│
  (tag: "5" → tag: "6")                    │
                                    ArgoCD detects change
                                            ↓
                                    Deploy to KIND cluster
                                            ↓
                                    App is live ✅
```

---

## 📁 Repository Structure

```
retail-store-gitops/
│
├── argocd-app.yaml              ← ArgoCD Application manifest
│                                  Apply once to bootstrap ArgoCD
│
├── helm/                        ← Helm chart for all 5 services
│   ├── Chart.yaml               ← Chart metadata
│   ├── values.yaml              ← Single source of truth
│   │                              Jenkins updates image tags here
│   └── templates/               ← Kubernetes manifest templates
│       ├── namespace.yaml       ← Creates 'retail' namespace
│       ├── ui-deployment.yaml
│       ├── ui-service.yaml
│       ├── catalog-deployment.yaml
│       ├── catalog-service.yaml
│       ├── cart-deployment.yaml
│       ├── cart-service.yaml
│       ├── orders-deployment.yaml
│       ├── orders-service.yaml
│       ├── checkout-deployment.yaml
│       ├── checkout-service.yaml
│       └── ingress.yaml         ← Routes / → ui service
│
├── devops/
│   ├── terraform/               ← AWS infrastructure code
│   │   ├── main.tf              ← EC2 instance
│   │   ├── network.tf           ← VPC, Subnet, IGW, SG
│   │   ├── variables.tf         ← Input variables
│   │   ├── outputs.tf           ← EC2 IP output
│   │   ├── terraform.tf         ← S3 backend + providers
│   │   ├── provider.tf          ← AWS provider
│   │   └── terraform.tfvars     ← (gitignored — contains real values)
│   │
│   └── ansible/
│       ├── ansible.cfg          ← SSH key, remote user config
│       ├── inventory.ini        ← (gitignored — contains EC2 IP)
│       ├── inventory.ini.example ← Template for inventory.ini
│       └── setup-server.yml     ← Master playbook
│
├── .gitignore
└── README.md
```

---

## ⎈ Helm Chart

### Chart.yaml

```yaml
apiVersion: v2
name: retail-store
description: GitOps Helm Chart for Retail Store Microservices
type: application
version: 0.1.0
appVersion: "1.0.0"
```

### values.yaml — The Single Source of Truth

```yaml
namespace: retail

ui:
  image: your-dockerhub/retail-store-ui
  tag: "v1"                    # ← Jenkins updates this on every build
  resources:
    requests: { cpu: "50m", memory: "128Mi" }
    limits:   { cpu: "200m", memory: "256Mi" }

catalog:
  image: your-dockerhub/retail-store-catalog
  tag: "v1"
  resources:
    requests: { cpu: "50m", memory: "64Mi" }
    limits:   { cpu: "100m", memory: "128Mi" }

# ... cart, orders, checkout follow same pattern
```

### Deployment Template Pattern

Every deployment template includes:

```yaml
# Resource limits — required for HPA and good practice
resources:
  requests:
    cpu: "{{ .Values.ui.resources.requests.cpu }}"
    memory: "{{ .Values.ui.resources.requests.memory }}"
  limits:
    cpu: "{{ .Values.ui.resources.limits.cpu }}"
    memory: "{{ .Values.ui.resources.limits.memory }}"

# Readiness probe — K8s stops traffic if this fails
readinessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 90    # Java Spring Boot needs time to start
  periodSeconds: 10
  failureThreshold: 5

# Liveness probe — K8s restarts pod if this fails
livenessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 120
  periodSeconds: 15
  failureThreshold: 5
```

### Service Template Pattern

All services are ClusterIP — only accessible inside the cluster:

```yaml
spec:
  type: ClusterIP        # Internal only — exposed via Ingress
  ports:
    - port: 8080         # Service port (what callers use)
      targetPort: 8080   # Container port (what app listens on)
```

### Ingress

```yaml
# Routes all traffic to UI service
# UI then calls other services internally
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ui
                port:
                  number: 8080
```

### Test Helm Rendering

```bash
# Render all templates to plain YAML (no deployment)
helm template retail-store helm/

# Lint for errors
helm lint helm/
```

---

## 🔧 How Jenkins Updates This Repo

Jenkins Stage 4 runs this shell script:

```bash
# Clone this repo
git clone https://$GH_TOKEN@github.com/USER/retail-store-gitops.git
cd retail-store-gitops

# Update ALL image tags in values.yaml
# Before: tag: "5"
# After:  tag: "6"
sed -i 's|tag: ".*"|tag: "'$BUILD_NUMBER'"|g' helm/values.yaml

# Commit and push
git config user.email "jenkins@ci.local"
git config user.name "Jenkins CI"
git add helm/values.yaml
git commit -m "ci: bump all image tags to $BUILD_NUMBER [skip ci]"
git push
```

**`[skip ci]`** in the commit message prevents Jenkins from triggering again on this push — avoiding an infinite loop.

---

## 🔄 How ArgoCD Uses This Repo

ArgoCD is configured via `argocd-app.yaml`:

```yaml
spec:
  source:
    repoURL: https://github.com/USER/retail-store-gitops.git
    targetRevision: main       # Watch the main branch
    path: helm                 # Use the helm/ folder as the chart
  destination:
    namespace: retail          # Deploy to retail namespace
  syncPolicy:
    automated:
      prune: true              # Delete resources removed from Git
      selfHeal: true           # Revert manual kubectl changes
    syncOptions:
      - CreateNamespace=true   # Create namespace if not exists
```

### ArgoCD Sync Flow

```
ArgoCD polls this repo every 3 minutes
         ↓
Detects values.yaml changed (new commit hash)
         ↓
Compares desired state (Git) vs actual state (cluster)
         ↓
Finds image tag mismatch → sync needed
         ↓
Pulls new images from DockerHub
         ↓
Rolling update: new pods → readinessProbe → old pods terminate
         ↓
Sync complete ✅
```

### Bootstrap ArgoCD (One-time)

```bash
# On EC2, after ArgoCD is installed
kubectl apply -f argocd-app.yaml

# Watch ArgoCD deploy everything
kubectl get pods -n retail -w
```

---

## 🌐 Infrastructure (Terraform)

See full documentation in the [app-source repo](https://github.com/HarjotSingh2k19/retail-store-sample-app).

**Quick start:**
```bash
cd devops/terraform

# Copy example and fill in values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform apply
```

### After EC2 Restart (IP Changes)

```bash
# 1. Get new EC2 IP
aws ec2 describe-instances \
  --instance-ids YOUR_INSTANCE_ID \
  --region ap-south-1 \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text

# 2. Update your home IP
curl -s https://checkip.amazonaws.com

# 3. Update terraform.tfvars with both new IPs
# 4. Apply (updates SSH security group rule)
terraform apply

# 5. Update inventory.ini with new EC2 IP
cat > devops/ansible/inventory.ini << 'EOF'
[servers]
NEW_EC2_IP
EOF

# 6. Update Jenkins webhook URL in GitHub
# Settings → Webhooks → Edit → http://NEW_EC2_IP:8080/github-webhook/
```

---

## ⚙️ Configuration (Ansible)

```bash
# Create inventory.ini (gitignored)
cp devops/ansible/inventory.ini.example devops/ansible/inventory.ini
# Edit: replace YOUR_EC2_PUBLIC_IP_HERE with real IP

# Run playbook
cd devops/ansible
ansible-playbook setup-server.yml
```

---

## ⏪ Rollback Guide

### Option 1 — Rollback via Git (Recommended)

```bash
# Revert values.yaml to previous commit
git log helm/values.yaml                    # find commit hash
git revert HEAD                             # revert last commit
git push origin main

# ArgoCD detects revert and redeploys old images automatically
```

### Option 2 — Helm Rollback

```bash
# On EC2
helm history retail-store -n retail         # see revision history
helm rollback retail-store 2 -n retail      # rollback to revision 2
```

### Option 3 — Manual values.yaml edit

```bash
# Edit values.yaml directly on GitHub or locally
# Change tag from "6" back to "5"
# Commit and push
# ArgoCD auto-deploys
```

---

## 🏗️ Full Restore from Scratch

If EC2 is terminated and you need to start fresh:

```bash
# 1. Provision new EC2
cd devops/terraform && terraform apply

# 2. Install all software
cd devops/ansible && ansible-playbook setup-server.yml

# 3. SSH into new EC2
ssh -i ~/.ssh/gitops-factory-key.pem ubuntu@NEW_EC2_IP

# 4. Create KIND cluster
kind create cluster --config kind-config.yaml

# 5. Install NGINX Ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# 6. Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 7. Bootstrap ArgoCD (one command restores everything)
kubectl apply -f argocd-app.yaml

# Done — ArgoCD deploys all services from this repo automatically ✅
```

---

## 📊 Monitoring (Optional)

```bash
# Install Prometheus + Grafana
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.retention=24h \
  --set alertmanager.enabled=false

# Access Grafana (from your Mac)
ssh -i ~/.ssh/gitops-factory-key.pem \
  -L 3000:localhost:3000 \
  ubuntu@EC2_IP \
  "kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring --address 127.0.0.1"

# Import dashboards: 6417 (K8s Cluster) and 1860 (Node Exporter)
```

---

## 👨‍💻 Author

**Harjot Singh**
- GitHub: [@HarjotSingh2k19](https://github.com/HarjotSingh2k19)
- LinkedIn: [harjot-singh-579ba9184](https://linkedin.com/in/harjot-singh-579ba9184)
- MCS Student — University of Ottawa (Fall 2026)

---

> ⭐ If this project helped you, please star both repos!
> - [retail-store-sample-app](https://github.com/HarjotSingh2k19/retail-store-sample-app)
> - [retail-store-gitops](https://github.com/HarjotSingh2k19/retail-store-gitops)
