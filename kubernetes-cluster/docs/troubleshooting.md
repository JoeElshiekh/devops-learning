# Kubernetes Troubleshooting

This document records the main issues encountered while building and validating the two-node Kubernetes lab.

The goal is not only to show the final working state, but also to document how problems were identified and resolved using Kubernetes and Linux troubleshooting tools.

The main issues covered are:

1. kubelet repeatedly restarting before `kubeadm init`
2. BusyBox test Pods completing immediately
3. ingress-nginx stuck in `ContainerCreating`
4. CoreDNS and cross-node Pod networking failing after enabling UFW
5. kubectl failing before kubeconfig was configured
6. validating API reachability vs authentication
7. checking Service and Ingress paths layer by layer

---

## 1. Troubleshooting Approach

The general troubleshooting method used throughout the lab was:

```text
Observe symptom
    ↓
Identify affected layer
    ↓
Inspect status/events/logs
    ↓
Test the dependency below it
    ↓
Change one thing
    ↓
Retest

The main tools used were:
kubectl get
kubectl describe
kubectl logs
kubectl get events
ping
traceroute
nslookup
wget
curl
nc
systemctl
journalctl
ip addr
ip route
ufw

The most important lesson was:
Do not troubleshoot the whole stack at once. First identify whether the issue is at the Pod, Service, DNS, CNI, node, firewall, or API layer.

2. kubelet Repeatedly Restarting Before Cluster Initialization
Symptom
Before kubeadm init, the control-plane kubelet showed:
Active: activating (auto-restart)
Result: exit-code

The restart counter kept increasing.
Example:
restart counter is at 500

Investigation
The kubelet service logs were checked using:
journalctl -u kubelet -n 20 --no-pager

The important error was:
failed to load kubelet config file
/var/lib/kubelet/config.yaml
no such file or directory

Cause
The kubelet package had been installed, but the cluster had not yet been initialized with kubeadm.
The file:
/var/lib/kubelet/config.yaml

is generated during kubeadm initialization.
So the kubelet had no final Kubernetes node configuration yet.
Resolution
No direct kubelet fix was required.
After:
sudo kubeadm init ...

the required kubelet configuration was created and kubelet started normally.
Lesson
A failing kubelet before kubeadm init does not always mean the kubelet installation is broken.
Always inspect:
journalctl -u kubelet

before attempting random fixes.
3. kubectl Could Not Connect Before kubeconfig Was Configured
Symptom
Running:
kubectl version

returned:
The connection to the server localhost:8080 was refused

Cause
kubectl was installed, but no valid kubeconfig existed yet.
The default file:
~/.kube/config

was missing.
Resolution
After kubeadm init, the generated admin kubeconfig was copied:
mkdir -p $HOME/.kube

sudo cp -i \
  /etc/kubernetes/admin.conf \
  $HOME/.kube/config

sudo chown \
  $(id -u):$(id -g) \
  $HOME/.kube/config

Verification
kubectl get nodes

started communicating with the API server successfully.
Lesson
Installing kubectl is not enough.
kubectl also needs:
cluster endpoint
credentials
certificate authority
context

which are provided through kubeconfig.
4. Control Plane Initially Showed NotReady
Symptom
After successful kubeadm init:
k8s-control   NotReady

CoreDNS Pods also remained:
Pending

Cause
No CNI plugin had been installed yet.
Kubernetes knew the Pod CIDR:
10.244.0.0/16

but no network implementation existed.
Resolution
Flannel was installed:
kubectl apply -f \
  https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

Verification
kubectl get nodes

changed to:
k8s-control   Ready

CoreDNS also became:
Running

Lesson
A fresh kubeadm node may remain NotReady until a CNI plugin is installed.
5. BusyBox Test Pods Entered Completed State
Symptom
Temporary networking Pods were created using BusyBox.
They quickly changed to:
Completed

Attempting:
kubectl exec ...

returned:
cannot exec into a container in a completed pod

Cause
BusyBox started, ran its default process, and exited successfully.
A container remains running only while its main process is running.
Resolution
The Pods were recreated with a long-running command:
sleep 3600

Example:
kubectl run test-worker \
  --image=busybox:1.36 \
  --restart=Never \
  --command -- sleep 3600

Verification
The Pod showed:
Running

and commands such as:
kubectl exec ...

worked.
Lesson
For temporary troubleshooting Pods, always provide a long-running process if interactive testing is required.
6. Cross-Node Pod Networking Verification
Goal
Verify that Pods on different nodes could communicate.
Example Pod networks:
k8s-control   -> 10.244.0.0/24
k8s-worker01  -> 10.244.1.0/24

Test
Traceroute from control-side Pod:
kubectl exec test-control -- traceroute 10.244.1.5

Example path:
1  10.244.0.1
2  10.244.1.0
3  10.244.1.5

Reverse test:
kubectl exec test-worker01 -- traceroute 10.244.0.6

Result
Bidirectional communication worked.
Lesson
Node status alone is not enough.
A Ready node does not prove that cross-node Pod traffic works.
Always validate actual Pod-to-Pod connectivity.
7. ingress-nginx Stayed in ContainerCreating
Symptom
The ingress-nginx controller remained:
ContainerCreating

for several minutes.
Attempting to read logs returned:
container "controller" ... is waiting to start

Investigation
The Pod was inspected using:
kubectl describe pod \
  ingress-nginx-controller-... \
  -n ingress-nginx

The Events section showed:
FailedMount
secret "ingress-nginx-admission" not found

and:
Pulling image ...

The image pull eventually took around 7 minutes.
Further Investigation
Cluster events were checked using:
kubectl get events \
  -n ingress-nginx \
  --sort-by=.lastTimestamp

Later events showed:
Successfully pulled image
Container created
Container started
NGINX reload triggered

Result
The Pod changed to:
1/1 Running

Lesson
If a Pod is stuck in ContainerCreating, kubectl logs may not help because the container has not started yet.
Use:
kubectl describe pod
kubectl get events

first.
8. ingress-nginx Returned 404 Before Any Ingress Rule Existed
Symptom
The controller was reachable through:
192.168.178.111:31401

but returned:
404 Not Found
nginx

Cause
This was expected.
The ingress-nginx controller was running, but there was no Ingress routing rule yet.
Interpretation
The 404 proved:
NodePort reachable      OK
ingress-nginx running   OK
HTTP request received   OK
Application route       missing

Resolution
A Kubernetes Ingress resource was created for:
Host: juice.local
Path: /

Backend:
juice-shop:3000

Lesson
An Ingress Controller and an Ingress resource are different things.
Ingress Controller
→ processes HTTP traffic

Ingress resource
→ defines routing rules

9. Juice Shop Service Worked by IP but Not by DNS
Symptom
The Juice Shop ClusterIP worked:
kubectl exec svc-test -- \
  wget -qO- http://10.101.119.191:3000

The application HTML was returned.
But DNS failed:
kubectl exec svc-test -- nslookup juice-shop

with:
connection timed out
no servers could be reached

Initial Conclusion
The application itself was healthy.
The Service itself was healthy.
The issue was specifically DNS or the path to CoreDNS.
10. CoreDNS Investigation
The test Pod had correct DNS configuration:
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local

The DNS Service existed:
kube-dns
10.96.0.10

CoreDNS EndpointSlices showed:
10.244.0.7
10.244.0.8

CoreDNS Pods were:
Running

Direct Test
From the worker-side test Pod:
kubectl exec svc-test -- ping -c 3 10.244.0.7

Result:
100% packet loss

The same happened for:
10.244.0.8

Conclusion
The problem was broader than DNS.
Cross-node Pod traffic from worker to control was being blocked.
11. UFW Broke Kubernetes Routed Traffic
Symptom
CoreDNS and cross-node Pod communication stopped working after UFW was enabled.
UFW status showed:
Default:
deny incoming
allow outgoing
deny routed

Important Observation
Linux IP forwarding was enabled:
net.ipv4.ip_forward = 1

but this only means:
Linux is allowed to forward packets

UFW still had the ability to block forwarded traffic.
So:
ip_forward = 1

did not override:
UFW routed policy = DENY

Diagnostic Test
UFW was temporarily disabled:
sudo ufw disable

Immediately afterward:
kubectl exec svc-test -- \
  nslookup juice-shop.default.svc.cluster.local

started working.
Root Cause
UFW was blocking routed Pod traffic between:
10.244.0.0/24

and:
10.244.1.0/24

12. UFW Fix
Instead of disabling UFW permanently, an explicit Kubernetes Pod routing rule was added:
sudo ufw route allow \
  from 10.244.0.0/16 \
  to 10.244.0.0/16

Flannel VXLAN traffic was also allowed:
sudo ufw allow \
  from 192.168.178.111 \
  to 192.168.178.110 \
  port 8472 \
  proto udp

Verification
After re-enabling UFW:
sudo ufw enable

CoreDNS worked:
kubectl exec svc-test -- \
  nslookup kubernetes.default.svc.cluster.local

returned:
10.96.0.1

and:
kubectl exec svc-test -- \
  nslookup juice-shop.default.svc.cluster.local

returned:
10.101.119.191

Cross-node Pod ping also worked again.
Lesson
A host firewall can affect Kubernetes overlay networking.
When enabling firewalls on Kubernetes nodes, consider:
API traffic
Pod routing
CNI traffic
Service traffic
DNS traffic

not only normal host ports.
13. API Server Returned 403
Test
From the worker node:
curl -k https://192.168.178.110:6443

returned:
403 Forbidden
User "system:anonymous" cannot get path "/"

Interpretation
This was not a connectivity failure.
It proved:
TCP connection         OK
TLS                    OK
API server reachable   OK
Authentication         not supplied
Authorization          denied

Lesson
A 403 from the Kubernetes API can actually prove that the network and TLS layers are functioning correctly.
14. Testing API Port Reachability
Windows Host
Test-NetConnection 192.168.178.110 -Port 6443

Expected:
TcpTestSucceeded : True

Worker
nc -zv 192.168.178.110 6443

Expected:
succeeded

Lesson
Use low-level port testing before blaming Kubernetes authentication or RBAC.
15. Juice Shop Deployment Verification
The Juice Shop Pod was inspected using:
kubectl describe pod juice-shop-...

Important information included:
Status: Running
Ready: True
Port: 3000/TCP
Node: k8s-worker01
IP: 10.244.1.10

The Deployment showed:
1/1 Ready

Lesson
For application troubleshooting, verify:
Deployment
ReplicaSet
Pod
Container state
Pod IP
Node placement
Events

before troubleshooting Service or Ingress.
16. Juice Shop Service Verification
The Service was inspected using:
kubectl describe svc juice-shop

Important output:
ClusterIP: 10.101.119.191
Port: 3000
TargetPort: 3000
Endpoints: 10.244.1.10:3000

EndpointSlice verification:
kubectl get endpointslice \
  -l kubernetes.io/service-name=juice-shop

Lesson
If a Service has no endpoints, the selector probably does not match any Pods.
Always compare:
Service selector

with:
Pod labels

17. Ingress Verification
The Ingress was checked using:
kubectl describe ingress juice-shop-ingress

Important output:
Ingress Class: nginx
Host: juice.local
Path: /
Backend:
juice-shop:3000

The backend resolved to:
10.244.1.10:3000

Lesson
If Ingress fails, validate in this order:
Pod
  ↓
Service
  ↓
Ingress backend
  ↓
Ingress Controller
  ↓
NodePort
  ↓
External client

Do not start with the browser.
18. Layer-by-Layer Troubleshooting Model
The most useful troubleshooting model from this lab was:
Application
    ↓
Pod
    ↓
Service
    ↓
EndpointSlice
    ↓
DNS
    ↓
Ingress
    ↓
Ingress Controller
    ↓
NodePort
    ↓
Node Network
    ↓
Firewall

For control-plane issues:
kubectl
   ↓
kubeconfig
   ↓
API Server
   ↓
Authentication
   ↓
Authorization

For cluster networking:
Pod
   ↓
CNI
   ↓
Flannel VXLAN
   ↓
Node routing
   ↓
Firewall
   ↓
Remote Pod

19. Useful Kubernetes Troubleshooting Commands
Nodes
kubectl get nodes -o wide
kubectl describe node <node-name>

Pods
kubectl get pods -A -o wide
kubectl describe pod <pod-name>
kubectl logs <pod-name>

Deployment
kubectl get deployment
kubectl describe deployment <name>

Services
kubectl get svc
kubectl describe svc <name>

EndpointSlices
kubectl get endpointslice -A

Ingress
kubectl get ingress
kubectl describe ingress <name>

Events
kubectl get events -A \
  --sort-by=.lastTimestamp

DNS
kubectl exec <pod> -- \
  cat /etc/resolv.conf

kubectl exec <pod> -- \
  nslookup <service-name>

Connectivity
kubectl exec <pod> -- ping <ip>
kubectl exec <pod> -- traceroute <ip>

20. Useful Linux Troubleshooting Commands
Networking
ip addr
ip route

DNS
resolvectl status

Ports
nc -zv <ip> <port>

HTTP/TLS
curl -k https://<ip>:<port>

Services
systemctl status kubelet
systemctl status containerd

Logs
journalctl -u kubelet
journalctl -u containerd

Firewall
sudo ufw status verbose
sudo ufw status numbered

Kernel
sysctl net.ipv4.ip_forward
lsmod | grep br_netfilter
lsmod | grep overlay

21. Key Troubleshooting Lessons
Inspect before changing
Use:
kubectl describe
kubectl get events
journalctl

before applying fixes.
Test one layer at a time
Example:
Pod works?
Service works?
DNS works?
Ingress works?
External access works?

A running Pod does not prove networking works
Always validate:
Pod-to-Pod
Pod-to-Service
DNS
cross-node traffic

Firewalls can break Kubernetes internally
Host firewalls must account for:
Pod forwarding
CNI traffic
API traffic
DNS traffic

Completed containers are not broken
A container may be in:
Completed

because its process ended successfully.
403 can mean networking is healthy
A Kubernetes API 403 Forbidden can prove:
network
TLS
API server

are all working.
Events are extremely valuable
Many Kubernetes startup problems are explained directly in:
kubectl describe pod
kubectl get events
