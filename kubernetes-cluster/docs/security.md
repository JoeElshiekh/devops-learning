# Kubernetes Security

This document describes the security controls and security concepts used in the two-node Kubernetes lab.

The main security areas covered are:

1. Network-level access control
2. Kubernetes API protection
3. TLS and certificates
4. Authentication
5. Authorization and RBAC
6. Bootstrap credentials
7. Firewall interaction with Kubernetes networking

---

## 1. Security Layers

Kubernetes security should be understood as multiple independent layers.

```text
Network Access
    ↓
Authentication
    ↓
Authorization
    ↓
Kubernetes Resource Access

These layers answer different questions.
Network Access
Can this source reach the Kubernetes API server?

Handled in this lab using UFW.
Authentication
Who are you?

Handled using Kubernetes credentials and certificates.
Authorization
What are you allowed to do?

Handled by Kubernetes RBAC and authorization policies.
A successful network connection does not automatically mean the client is allowed to use Kubernetes.
2. Kubernetes API Server
The Kubernetes API server is the main entry point into the cluster.
In this lab it listens on:
192.168.178.110:6443

The API server is used by:
- kubectl
- kubelet
- controllers
- cluster components
- administrators
- automation tools
Because the API server controls cluster resources, access to port 6443 was restricted.
3. API Network Access Restriction
The lab uses UFW on the control-plane node.
The firewall policy is:
Default incoming: DENY
Default outgoing: ALLOW
Default routed: DENY

API access is allowed only from approved sources.
Allowed IPs:
192.168.178.1
Windows management host

192.168.178.111
k8s-worker01

Example rules:
sudo ufw allow 22/tcp

sudo ufw allow from 192.168.178.1 \
  to any port 6443 \
  proto tcp

sudo ufw allow from 192.168.178.111 \
  to any port 6443 \
  proto tcp

This means other hosts on the network cannot directly reach the Kubernetes API server unless explicitly allowed.
4. Verifying API Access
API reachability from the Windows management host was tested using:
Test-NetConnection 192.168.178.110 -Port 6443

Successful result:
TcpTestSucceeded : True

The worker node was tested using:
nc -zv 192.168.178.110 6443

and:
curl -k https://192.168.178.110:6443

The unauthenticated curl request returned:
403 Forbidden

This was expected.
It proved:
Network connectivity  OK
TLS connection        OK
Authentication        missing
Authorization         denied

This demonstrates the difference between reaching the API server and being authorized to use it.
5. TLS
Kubernetes uses TLS to protect communication between cluster components.
During kubeadm init, Kubernetes generated certificates for:
- Kubernetes API server
- API server to kubelet communication
- etcd
- controller manager
- scheduler
- service accounts
- cluster certificate authorities
The certificates are stored under:
/etc/kubernetes/pki

The generated kubeconfig files are stored under:
/etc/kubernetes

6. API Server Certificate SANs
The control plane was initialized with:
--apiserver-cert-extra-sans=controlplane

SAN means:
Subject Alternative Name

This adds an additional valid DNS name to the API server certificate.
The API server certificate was generated for names including:
controlplane
k8s-control
kubernetes
kubernetes.default
kubernetes.default.svc
kubernetes.default.svc.cluster.local

and IP addresses including:
192.168.178.110
10.96.0.1

This allows TLS validation when accessing the API server using an included DNS name or IP address.
7. Authentication
Authentication answers:
Who is making this request?

The regular administrator uses the kubeconfig file:
~/.kube/config

This file was copied from:
/etc/kubernetes/admin.conf

Example setup:
mkdir -p $HOME/.kube

sudo cp -i \
  /etc/kubernetes/admin.conf \
  $HOME/.kube/config

sudo chown \
  $(id -u):$(id -g) \
  $HOME/.kube/config

The kubeconfig contains the information needed by kubectl to connect securely to the API server.
This includes:
- cluster endpoint
- certificate authority information
- client credentials
- Kubernetes context
8. kubeconfig
The kubeconfig tells kubectl:
Which cluster should I connect to?
Which user identity should I use?
Which namespace/context should I use?

Without a valid kubeconfig, kubectl could not correctly access the cluster.
Before kubeconfig was configured, kubectl returned:
The connection to the server localhost:8080 was refused

After configuring:
~/.kube/config

kubectl successfully communicated with the API server.
9. Authorization
Authorization answers:
What is this authenticated identity allowed to do?

Kubernetes uses authorization mechanisms such as RBAC.
RBAC stands for:
Role-Based Access Control

RBAC permissions can be defined using:
- Roles
- ClusterRoles
- RoleBindings
- ClusterRoleBindings
This lab mainly focused on API network restriction and cluster administration.
No custom application RBAC policies were required for the Juice Shop deployment.
10. Authentication vs Authorization
The difference is important.
Authentication
→ Who are you?

Authorization
→ What are you allowed to do?

Example:
User connects to API server
        ↓
Certificate/token proves identity
        ↓
Authentication succeeds
        ↓
RBAC checks requested operation
        ↓
Authorization allows or denies

A client may be successfully authenticated but still receive:
403 Forbidden

if RBAC does not allow the requested action.
11. Bootstrap Token
During kubeadm init, Kubernetes generated a bootstrap token.
The token was used when joining the worker node.
Example structure:
sudo kubeadm join 192.168.178.110:6443 \
  --token <bootstrap-token> \
  --discovery-token-ca-cert-hash sha256:<ca-hash>

The token allows the new node to begin the secure bootstrap process.
The discovery hash verifies the cluster certificate authority.
This helps prevent the worker from accidentally joining an untrusted API server.
12. Sensitive Credentials
The following information should not be committed to GitHub:
Bootstrap tokens
Private certificates
Private keys
admin.conf
super-admin.conf
kubelet credentials
Service account private keys

For this reason, the real kubeadm join token and CA discovery hash are not stored in the repository.
Documentation only contains the command structure:
kubeadm join <control-plane>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>

13. Control-Plane Scheduling Protection
The control-plane node was automatically marked with the taint:
node-role.kubernetes.io/control-plane:NoSchedule

This prevents normal application Pods from being scheduled on the control-plane node.
Conceptually:
Control Plane
    ↓
Kubernetes system components

Worker Node
    ↓
Application workloads

The Juice Shop workload was therefore scheduled on:
k8s-worker01

This keeps application workloads separate from critical control-plane components.
14. Service Accounts
Kubernetes Pods receive a ServiceAccount identity.
The Juice Shop Pod used the default ServiceAccount:
Service Account: default

Kubernetes automatically mounted ServiceAccount-related data under:
/var/run/secrets/kubernetes.io/serviceaccount

ServiceAccounts are used when workloads need to authenticate to the Kubernetes API.
In this lab, Juice Shop did not require Kubernetes API access.
15. UFW and Pod Networking
Enabling UFW initially caused a Kubernetes networking problem.
The default UFW policy included:
deny (routed)

This blocked forwarded traffic between Pod networks.
Symptoms included:
CoreDNS timeouts
Pod-to-Pod ping failures
Service DNS failures

Example:
nslookup juice-shop
connection timed out

The issue was confirmed by temporarily disabling UFW.
DNS immediately started working again.
16. Allowing Kubernetes Routed Traffic
Instead of disabling UFW permanently, an explicit route rule was added.
sudo ufw route allow \
  from 10.244.0.0/16 \
  to 10.244.0.0/16

This allows Kubernetes Pod traffic to be forwarded while keeping the default routed policy restrictive.
The resulting security model is:
Default routed traffic
DENY

Kubernetes Pod traffic
ALLOW

17. Flannel VXLAN Firewall Rule
Flannel uses VXLAN for cross-node Pod communication.
The VXLAN port used is:
UDP/8472

The control plane allows VXLAN traffic from the worker:
sudo ufw allow \
  from 192.168.178.111 \
  to 192.168.178.110 \
  port 8472 \
  proto udp

If UFW is enabled on the worker in the future, the reciprocal rule should also be configured there.
Example:
sudo ufw allow \
  from 192.168.178.110 \
  to 192.168.178.111 \
  port 8472 \
  proto udp

18. Firewall Policy
Final control-plane firewall design:
SSH
TCP/22
ALLOW

Kubernetes API
TCP/6443
ALLOW only:
192.168.178.1
192.168.178.111

Flannel VXLAN
UDP/8472
ALLOW from worker

Pod Network
10.244.0.0/16
ALLOW routed Pod-to-Pod traffic

Everything else
DENY according to default policy

This provides a restrictive default posture while allowing the Kubernetes cluster to operate correctly.
19. Security Flow
Windows Host
192.168.178.1
      |
      | TCP/6443 allowed
      v
Kubernetes API Server
192.168.178.110:6443
      |
      v
TLS
      |
      v
Authentication
      |
      v
Authorization / RBAC
      |
      v
Kubernetes Resources

Worker access follows the same pattern:
k8s-worker01
192.168.178.111
      |
      | TCP/6443 allowed
      v
API Server
      |
      v
TLS
      |
      v
Node credentials
      |
      v
Authorized kubelet operations

20. Security Verification Commands
Check UFW:
sudo ufw status verbose

Check API port from Windows:
Test-NetConnection 192.168.178.110 -Port 6443

Check API port from worker:
nc -zv 192.168.178.110 6443

Test unauthenticated API request:
curl -k https://192.168.178.110:6443

Inspect cluster certificates:
sudo ls -la /etc/kubernetes/pki

Inspect kubeconfig:
kubectl config view

Check control-plane taints:
kubectl describe node k8s-control

Check ServiceAccount used by a Pod:
kubectl get pod \
  -o custom-columns=NAME:.metadata.name,SERVICEACCOUNT:.spec.serviceAccountName
