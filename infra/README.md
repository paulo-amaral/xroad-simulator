# Infrastructure: deploy the X-Road Security Server

Three deployment targets, one shared install role:

| Target | Where | How |
|---|---|---|
| **Docker** | local dev / demo | The runnable sandbox: [../sandboxes/timor-leste/docker-compose.yml](../sandboxes/timor-leste/docker-compose.yml) (`docker compose up -d`). |
| **Kubernetes** | cluster / scale | Sidecar manifests in [kubernetes/](kubernetes/security-server.yaml): `kubectl apply -f kubernetes/security-server.yaml` (one StatefulSet per ministry), then provision with `xrdsst`. |
| **Local network** | real LAN hosts | Ansible install on real systemd hosts: copy [ansible/inventory.example.ini](ansible/inventory.example.ini) to `inventory.ini`, set `xroad_simulate=false`, run the playbook. |

The Terraform + Ansible matrix below is a fourth, **simulation-only** mode: it builds systemd containers (one
per distro) and runs the install role in check mode to validate repository wiring and dependency resolution
across Ubuntu and RHEL without touching real hosts.

> Every Security Server needs a **routable address** the others can reach on 5500/5577. In Docker that is the
> container hostname; in Kubernetes the headless-Service per-pod DNS; on a LAN the host's IP/DNS. Registering a
> server as `127.0.0.1` breaks all cross-server traffic (it loops back to itself).

> Simulation, not production. The container matrix proves the install role works per distro. A full,
> running Security Server still needs a real systemd host plus Central Server, CA, and configuration anchor
> (see the project sandbox: [../docs/sandbox.md](../docs/sandbox.md)).

## Distro matrix (default)

| Node | Image | Family |
|---|---|---|
| ubuntu2204 | geerlingguy/docker-ubuntu2204-ansible | Debian (apt) |
| ubuntu2404 | geerlingguy/docker-ubuntu2404-ansible | Debian (apt) |
| rocky8 | geerlingguy/docker-rockylinux8-ansible | RedHat (yum) |
| rocky9 | geerlingguy/docker-rockylinux9-ansible | RedHat (yum) |

Add or remove distros by editing `var.distros` in [terraform/variables.tf](terraform/variables.tf).

## Prerequisites

- Docker Engine (running).
- Terraform >= 1.5 with the `kreuzwerker/docker` provider (installed automatically by `terraform init`).
- Ansible with the Docker connection plugin: `ansible-galaxy collection install community.docker`.

## Run

```bash
# 1. Build the distro matrix and generate the Ansible inventory
cd infra/terraform
terraform init
terraform apply        # creates xroad-sim-* containers and ../ansible/inventory.ini

# 2. Simulate the install on every distro (check mode by default)
cd ../ansible
ansible-playbook -i inventory.ini site.yml

# 3. Tear down
cd ../terraform
terraform destroy
```

## Where each command runs

> `terraform` and `ansible-playbook` run on your host (the Docker client). Terraform creates the containers;
> Ansible runs on the host but connects *into* each container via the `community.docker` plugin and executes the
> install role there. So the orchestration is host-side, but the Security Server package step happens inside the
> container. Quick check: `uname -m` on the host vs `docker exec <node> uname -m` shows host vs container.

## Real install vs simulation

`xroad_simulate: true` (default in [the role defaults](ansible/roles/xroad_security_server/defaults/main.yml))
runs the package step in check mode: it adds the official repo and resolves `xroad-securityserver` without
hitting the interactive debconf prompts a real install triggers. To perform a full install on a real systemd
VM, set `xroad_simulate: false` and preseed debconf per the installation guide.

## Scope addendum: no cloud IaC

Cloud provisioning (AWS VPC/ECS/RDS Terraform modules, or any managed-service deploy) is deliberately out of
scope. The target is a local sandbox: Terraform builds throwaway systemd containers and Ansible installs the
Security Server package on them. A cloud module layer would be premature abstraction without a real environment
to justify it. Revisit only if a hosted, multi-environment deployment becomes a goal.

## High availability (production reference)

This sandbox runs a single Security Server per member for clarity; it is a functional demo, not an HA
setup. In production, X-Road Security Servers are made highly available by running several nodes in an
active-active cluster behind an external load balancer with a replicated database. Treat the **official
X-Road documentation as the authority**:

- X-Road external load balancer installation guide (official):
  <https://docs.x-road.global/Manuals/LoadBalancing/x-road_external_load_balancer_installation_guide.html>

A public real-world deployment of the same pattern is CamDX (Cambodia). Its install notes are a useful
**reference example only** — not a specification, and no CamDX endpoints or domains are used here:

- CamDX HA Security Server with external load balancer:
  <https://github.com/Techo-Startup-Center/CamDX-Documents/blob/main/high_availability_security_server_installation_with_external_load_balancer.md>

## Sources

- Security Server installation guide (repos, ports, debconf): https://docs.x-road.global/Manuals/ig-ss_x-road_v6_security_server_installation_guide.html
- Set up a Security Server (knowledge base): https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/4916118/
- community.docker connection plugin: https://docs.ansible.com/ansible/latest/collections/community/docker/
