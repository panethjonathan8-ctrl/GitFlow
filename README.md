# GitFlow Analyzer

A production-grade DevOps capstone project. Paste a GitHub repository URL and get back detected languages, frameworks, and a dependency graph showing how files and modules connect.

## Architecture

### Phase 1 (current)
- **App**: Python Flask monolith running in Docker on EC2
- **Infrastructure**: AWS VPC, EC2 t3.micro with Elastic IP, ECR, Secrets Manager
- **CI/CD**: GitHub Actions with OIDC — zero stored credentials anywhere
- **IaC**: Terraform with remote state in S3, state locking via S3 lockfile

### Phase 2 (planned)
- Split monolith into three microservices (analyzer, graph-builder, result-api)
- Migrate from EC2 to EKS (Kubernetes)
- Add ALB, private subnets, NAT gateway
- Add Prometheus and Grafana monitoring
- ArgoCD for GitOps deployments

## API Endpoints

### Health check
GET /health
Returns `{"status": "healthy"}` when the app is running correctly.

### Analyze a repository
POST /analyze
Content-Type: application/json
{"repo_url": "https://github.com/user/repo"}
Returns detected languages, frameworks, and a dependency graph of nodes and edges.

## Infrastructure
AWS Account (153772056450)
├── S3 bucket          — Terraform remote state, encrypted + versioned
├── VPC (10.0.0.0/16)
│   ├── Public subnet A — eu-west-1a (10.0.1.0/24)
│   └── Public subnet B — eu-west-1b (10.0.2.0/24)
├── Internet Gateway   — connects VPC to internet
├── EC2 t3.micro       — runs the Docker container
│   ├── Elastic IP     — fixed public IP, survives stop/start
│   ├── IAM role       — pulls from ECR, reads Secrets Manager
│   └── Security group — port 5000 open
├── ECR repos (×3)     — private Docker image registry
├── Secrets Manager    — GitHub token stored encrypted
└── IAM
├── OIDC provider  — trusts GitHub Actions tokens
└── GitHub Actions role — scoped to this repo only

## CI/CD Pipelines

### terraform-plan.yml
Triggers on every pull request that changes `terraform/` files.
- Authenticates to AWS via OIDC
- Runs `terraform plan`
- Posts plan output as a PR comment

### deploy.yml
Triggers on every push to `main` that changes `services/` files.
- Authenticates to AWS via OIDC
- Builds Docker image tagged with git SHA
- Pushes to ECR with both `:SHA` and `:latest` tags
- Deploys to EC2 via SSM (no SSH keys needed)
- Verifies health endpoint passes

## Local Development

```bash
# Clone
git clone https://github.com/panethjonathan8-ctrl/GitFlow
cd GitFlow

# Set up environment
cp services/app/.env.example services/app/.env
# Edit .env — set GITHUB_TOKEN to your personal access token

# Run
cd services/app
docker compose up

# Test
curl http://localhost:5000/health

curl -X POST http://localhost:5000/analyze \
  -H "Content-Type: application/json" \
  -d '{"repo_url": "https://github.com/pallets/flask"}'
```

## Manual Deploy

To trigger a deployment without pushing code:

```bash
./scripts/deploy.sh
```

## Security Decisions

| Decision | Reason |
|---|---|
| Root has MFA, no access keys | Prevents account takeover |
| IAM user has permissions boundary | Caps maximum permissions even if policy is misconfigured |
| GitHub Actions uses OIDC | Temporary credentials only — nothing stored in GitHub Secrets |
| EC2 uses IAM instance role | No access keys on the server |
| GitHub token in Secrets Manager | Never on disk, never in env files, never in git |
| Docker runs as non-root user | Limits blast radius if container is compromised |
| ECR images scanned on push | Catches known CVEs automatically |
| EBS volume encrypted | Data at rest cannot be read if disk is accessed directly |
| Elastic IP | Fixed address — API URL never changes |
