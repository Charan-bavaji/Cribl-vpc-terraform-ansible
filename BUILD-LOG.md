# Cribl VPC Project — Full Build Log

**Goal:** Use Terraform to build AWS infrastructure and Ansible to configure
software on top of it — demonstrating how the two tools work together.
End state: 3 EC2 instances running Cribl, behind an ALB, in a VPC peered
to a second VPC.

---

## Final Architecture

```
User → Internet Gateway (VPC1) → ALB (public subnet)
     → Target Group → 3x EC2 (private subnet, running Cribl)

Admin → Internet Gateway → Bastion (public subnet, SSH locked to admin IP)
      → private instances (SSH only from bastion)

Private instances → NAT Gateway (public subnet) → Internet Gateway
                   → internet (outbound only, e.g. downloading Cribl)

VPC2 (separate, own IGW) ←→ VPC Peering ←→ VPC1
  (proven working via ping between a VPC2 test instance and VPC1's bastion,
   entirely over private IPs — no internet involved)
```

Two security layers throughout: Security Groups (stateful, per-instance)
and NACLs (stateless, per-subnet).

---

## Phase-by-Phase: What We Built

**Phase 0 — Environment setup**
WSL2 Ubuntu 22.04, Terraform, AWS CLI, Ansible installed. IAM user
(`terraform-cribl`) created. S3 bucket + DynamoDB table for Terraform
remote state (so state isn't just a local file).

**Phase 1 — Project structure**
`modules/` (reusable Terraform building blocks: vpc, ec2, alb, route53,
peering) + `environments/dev/` (the actual deployment wiring modules
together) + `ansible/` (inventory, playbooks, roles).

**Phase 2 — VPC1**
VPC, 2 public + 2 private subnets across 2 AZs, Internet Gateway, route
tables, NAT Gateway (added later — see error log), NACLs on both public
and private subnets.

**Phase 3 — Compute**
Bastion host in the public subnet (SSH locked to one IP). 3 EC2
instances in the private subnets, tagged `Role=cribl` for Ansible's
dynamic inventory. Security groups: bastion accepts SSH only from
admin's IP; private instances accept SSH only from the bastion's
security group.

**Phase 4 — Ansible**
SSH agent forwarding through the bastion (private key never copied onto
the bastion itself). AWS dynamic inventory (finds instances by the
`Role=cribl` tag automatically — no hardcoded IPs). A `cribl` role:
dedicated non-root service user, systemd unit, download + extract +
start Cribl.

**Phase 5 — ALB**
Application Load Balancer in the public subnets, its own security group
(only thing allowed to accept traffic from `0.0.0.0/0`), target group
with a health check, 3 instances registered as targets. A cross-module
security group rule lets the ALB reach the private instances on Cribl's
port — added from the root config rather than baked into either module,
so the EC2 and ALB modules don't need to know about each other.

**Phase 6 — Route 53**
Deferred. A Private Hosted Zone was built and considered, but a private
zone only resolves inside the VPC — not shareable in a demo. Decided to
wait until a real domain is purchased, then use a Public Hosted Zone
instead (same mechanics, actually shareable).

**Phase 7 — VPC2 + Peering**
Clarified an important misconception first: peering does **not** let a
public user's traffic enter through one VPC and get proxied to another —
it only connects private IP space directly. Built VPC2 (own IGW, one
public subnet, no NAT needed) with a small test EC2 instance, peered to
VPC1, and proved the peering connection actually carries traffic by
pinging VPC1's bastion (private IP) from inside VPC2 — 4/4 packets,
0% loss.

---

## Every Error Hit, and the Actual Root Cause

### 1. AWS "Free Plan" blocked all paid instance types
**Symptom:** `InvalidParameterCombination: not eligible for Free Tier` —
even for instance types AWS's own API listed as free-tier eligible, and
even after switching between `t3.medium` → `t3.micro` → `t2.micro`.
**Root cause:** the AWS account was on a newer "Free Plan" account type
(different from classic Free Tier limits) that hard-blocks *any*
resource usage beyond free tier, using this same error message
regardless of the actual instance type.
**Fix:** upgraded to a paid plan via Billing Preferences.

### 2. EC2 key pair "not found"
**Symptom:** `InvalidKeyPair.NotFound` on `terraform apply`.
**Root cause:** the key pair was created while the AWS Console was
showing the wrong region (Stockholm) — key pairs are region-specific,
and Terraform was deploying to Mumbai.
**Fix:** created the key pair again in the correct region.

### 3. Duplicated project folder
**Symptom:** `~/cribl-project/cribl-project/` — nested one level too
deep.
**Root cause:** the zip already contained a `cribl-project` folder,
extracted into another folder also named `cribl-project`.
**Fix:** flattened it with `mv`/`rm`.

### 4. Multi-line command corrupted `environments/dev`
**Symptom:** `terraform plan` demanded variables (`name`, `cidr_block`)
that belonged to the VPC *module*, not the root config.
**Root cause:** a multi-line `cp` command got flattened into one line by
the terminal, so `cp`'s final argument (meant to start a second command)
was instead treated as another file to copy — overwriting
`environments/dev/main.tf` and `variables.tf` with the VPC module's own
files.
**Fix:** recovered from a clean zip extract, restored `terraform.tfvars`
separately. **Lesson adopted:** used `cat > file << 'EOF' ... EOF`
heredocs for all file creation from then on — immune to this failure
mode.

### 5. Ansible dynamic inventory collapsed 3 instances into 1
**Symptom:** `ansible-inventory --list` showed only one host, literally
named `"private_ip_address"`.
**Root cause:** the `hostnames` field needs AWS's hyphenated key style
(`private-ip-address`), not the underscore Python-style name
(`private_ip_address`) — the plugin didn't recognize it, so it used the
literal string as the hostname for every instance, causing a collision.
**Fix:** corrected the field name.

### 6. Ansible role not found
**Symptom:** `ERROR! the role 'cribl' was not found`.
**Root cause:** Ansible looks for roles inside the *playbook's own*
folder (`playbooks/roles/`) by default — the roles actually lived one
level up, alongside `playbooks/`, not inside it.
**Fix:** added `roles_path = ./roles` to `ansible.cfg`.

### 7. Cribl download failed — "Network is unreachable"
**Symptom:** the Ansible download task failed on all 3 private
instances.
**Root cause:** the private subnets had no NAT Gateway — no route out to
the internet at all, only routes within the VPC.
**Fix:** added a NAT Gateway + Elastic IP, and a default route in the
private route table pointing at it.

### 8. Guessed Cribl download URL was wrong
**Root cause:** Cribl's real download filenames include an unpredictable
build hash (e.g. `cribl-4.19.2-89cac507-linux-x64.tgz`) that can't be
derived from the version number alone.
**Fix:** got the real URL from Cribl's site via Chrome's downloads page
(the download button wasn't a plain right-clickable link).

### 9. Stale bastion IP after every rebuild
**Symptom:** SSH hop timeouts after a fresh `terraform apply`.
**Root cause:** the bastion gets a new public IP every time it's
recreated, but `~/.ssh/config` had the old one hardcoded.
**Fix:** established a routine — check `terraform output
bastion_public_ip` and update `~/.ssh/config` after every rebuild.

### 10. `ssh-agent` not active in a new terminal
**Symptom:** `Permission denied (publickey)` reaching private instances,
even though the bastion itself connected fine.
**Root cause:** `ssh-agent` only lives for the terminal session it was
started in — a new WSL window has no agent running and no key loaded.
**Fix:** re-run `eval "$(ssh-agent -s)"` + `ssh-add` in each new session.

### 11. VPC peering misconception
Peering does not let traffic enter through one VPC's IGW and exit
through another's — IGWs never talk to each other, peered or not.
Peering only connects private IP space directly between two VPCs.
Corrected the mental model before building VPC2, rather than after.

### 12. Ping across peering timed out (first attempt)
**Root cause:** NACLs are stateless — a rule was added allowing the ping
*request* into VPC1, but the *reply* leaving VPC1 back into VPC2 had no
matching rule on VPC2's own NACL, so it was silently dropped at the
door.
**Fix:** added the missing return-path NACL rule (ICMP type 0, echo
reply) on VPC2's NACL.

### 13. The big one: inline vs. standalone Terraform rules (hit 3 times)
**Symptom:** a working NACL rule or security group rule would vanish on
the *next* `terraform apply`, with no obvious cause.
**Root cause:** the VPC and EC2 modules originally defined routes,
NACL rules, and security group rules as *inline* blocks inside their
parent resource (`aws_route_table { route { ... } }`,
`aws_network_acl { ingress { ... } }`,
`aws_security_group { ingress { ... } }`). An inline-defined resource
treats itself as the *complete* authoritative list — so any rule added
separately elsewhere (like the peering module's cross-VPC routes, or the
root config's ALB→Cribl security group rule) gets silently deleted the
next time the inline-defined resource is applied, because Terraform sees
it as "not in my list."
This hit three separate resource types before it was caught for good:
route tables, then NACLs, then security groups.
**Fix:** converted every route table, NACL, and security group in both
modules from inline blocks to standalone resources (`aws_route`,
`aws_network_acl_rule`, `aws_security_group_rule`) — the standard
recommended pattern specifically because it avoids this class of bug.

### 14. Duplicate rule errors applying the above fix
**Symptom:** `InvalidPermission.Duplicate`, `RouteAlreadyExists`.
**Root cause:** the old inline-created rules still physically existed in
AWS; Terraform's plan showed pure "create" actions for the new
standalone resources without detecting the pre-existing duplicates,
since it wasn't tracking them under the new resource addresses.
**Fix:** rather than importing ~10+ individual resources one at a time,
did a full `terraform destroy` + fresh `apply` — clean rebuild, no
possible conflicts, since nothing old was left behind.

### 15. `terraform destroy` silently didn't take effect (once)
Ended a session believing everything was destroyed; came back to find
the bastion and all 3 Cribl instances still running and billable. Never
fully root-caused, but the fix going forward was simple: always wait to
see the literal `Destroy complete! Resources: X destroyed.` line before
closing the terminal, and verify in the console afterward.

---

## Key Lessons (interview-ready)

- **Terraform provisions, Ansible configures** — a clean separation of
  concerns, demonstrated end-to-end.
- **NACLs are stateless; security groups are stateful.** Built both,
  and personally debugged a stateless-return-path bug caused by that
  exact distinction.
- **VPC peering connects private IP space, not public traffic.** It
  doesn't proxy internet requests between VPCs, and IGWs never talk to
  each other.
- **Never mix inline resource blocks with standalone resources of the
  same type on the same parent** (routes, NACL rules, security group
  rules) — the inline block always "wins" and deletes anything added
  separately. This is a real, well-known Terraform gotcha, not a
  one-off mistake.
- **AWS's newer "Free Plan" account type is a genuinely different thing
  from classic Free Tier** — it hard-blocks any non-free resource
  outright, using the same error message regardless of cause.
- **Dynamic inventory (Ansible) beats hardcoded IPs** for anything that
  gets destroyed and rebuilt.
