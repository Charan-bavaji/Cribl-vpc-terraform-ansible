# Cribl VPC Project — Terraform + Ansible

Client-style project from ScoopLabs DevOps training: use Terraform to
provision AWS infrastructure and Ansible to configure software on top
of it, demonstrating how the two tools work together in practice.

**End result:** 3 EC2 instances running [Cribl](https://cribl.io) behind
an Application Load Balancer, in a VPC with public/private subnets,
NAT Gateway, a bastion host, layered security (Security Groups + NACLs),
and a second VPC connected via VPC Peering.

## Architecture

![Architecture diagram](docs/architecture-diagram.png)

```
User → Internet Gateway (VPC1) → ALB (2 public subnets)
     → Target Group → 3x EC2 (private subnets, running Cribl)

Admin → Internet Gateway → Bastion (SSH locked to admin IP)
      → private instances (SSH only from bastion)

Private instances → NAT Gateway → Internet Gateway → internet (outbound only)

VPC2 (own IGW) ←→ VPC Peering ←→ VPC1  (private IPs only, no internet)
```

## Stack

- **Terraform** — VPC, subnets, NAT Gateway, Internet Gateway, route
  tables, Security Groups, NACLs, bastion + EC2 instances, ALB + target
  group, VPC2 + peering connection
- **Ansible** — AWS dynamic inventory (finds instances by tag, not
  hardcoded IPs), SSH agent forwarding through the bastion, a `cribl`
  role that installs and runs Cribl as a systemd service under a
  dedicated non-root user

## Repo structure

```
modules/          Reusable Terraform modules (vpc, ec2, alb, peering, route53)
environments/dev/ The actual deployment, wiring modules together
ansible/          Inventory, playbooks, and the cribl role
```

## Notes

- `terraform.tfvars` is gitignored — copy `terraform.tfvars.example` and
  fill in your own values (region, CIDRs, your IP, key pair name).
- Route 53 (`modules/route53`) is built but not wired into the current
  deployment — a Private Hosted Zone only resolves inside the VPC, so
  it's deferred until a real domain is in place for a Public Hosted
  Zone instead.
- A full build log — every phase, every error hit, and the actual root
  cause and fix for each — is in [`BUILD-LOG.md`](./BUILD-LOG.md).
