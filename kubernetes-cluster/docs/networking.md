# Kubernetes Networking

This document explains the networking design used in the two-node Kubernetes lab and the troubleshooting performed during the setup.

The cluster uses three different network layers:

1. Node network
2. Pod network
3. Service network

Understanding the difference between these layers is important because each one solves a different problem.

---

## 1. Node Network

The Kubernetes nodes communicate over the VMware VMnet8 NAT network.

```text
Subnet: 192.168.178.0/24
Gateway: 192.168.178.2
DNS: 192.168.178.2

Node addresses:
Node	IP
k8s-control	192.168.178.110
k8s-worker01	192.168.178.111


The node network is the real Linux/VM network provided by VMware.
Example:
k8s-control
192.168.178.110
      |
      | VMware VMnet8
      |
192.168.178.111
k8s-worker01

This network is used for:
- control-plane communication
- kubelet communication
- Kubernetes API access
- Flannel VXLAN traffic
- node-to-node connectivity
Node connectivity was verified using:
ping 192.168.178.110
ping 192.168.178.111

2. Pod Network
The cluster-wide Pod network was configured during kubeadm init as:
10.244.0.0/16

Flannel is used as the CNI plugin to implement this network.
Each node receives a smaller Pod subnet from the cluster-wide CIDR.
Example:
k8s-control   -> 10.244.0.0/24
k8s-worker01  -> 10.244.1.0/24

Pods then receive addresses from the subnet assigned to the node where they run.
Example:
k8s-control
192.168.178.110
      |
      +-- CoreDNS Pod 10.244.0.7
      +-- CoreDNS Pod 10.244.0.8

k8s-worker01
192.168.178.111
      |
      +-- ingress-nginx Pod 10.244.1.8
      +-- Juice Shop Pod 10.244.1.10

The Pod IP belongs to the application workload.
The node IP belongs to the Linux machine.
These are different network identities.
3. CNI
CNI stands for:
Container Network Interface

The CNI plugin is responsible for connecting Pods to the Kubernetes network.
This lab uses Flannel.
Before Flannel was installed, the control-plane node showed:
NotReady

and CoreDNS Pods remained:
Pending

After Flannel was installed:
k8s-control   Ready
k8s-worker01  Ready

and CoreDNS started running normally.
4. Flannel
Flannel provides the Pod network for this cluster.
It creates and manages the overlay network between nodes.
The cluster Pod CIDR is:
10.244.0.0/16

Flannel uses VXLAN for cross-node Pod communication.
The basic idea is:
Pod
10.244.0.x
    |
    v
Flannel
    |
    | encapsulated traffic
    v
Node
192.168.178.110
    |
    | VMware Network
    v
Node
192.168.178.111
    |
    v
Flannel
    |
    v
Pod
10.244.1.x

The VMware network carries traffic between the nodes.
The Flannel overlay carries Pod traffic on top of that network.
5. VXLAN
VXLAN is the overlay mechanism used by Flannel in this lab.
Flannel VXLAN traffic uses:
UDP/8472

Conceptually:
Original Pod packet
10.244.0.x -> 10.244.1.x
        |
        v
Encapsulated inside VXLAN
        |
        v
192.168.178.110 -> 192.168.178.111
        |
        v
Remote node removes VXLAN encapsulation
        |
        v
Delivered to destination Pod

This allows Pods on different physical or virtual nodes to communicate as if they belong to one logical network.
6. Kernel Networking Requirements
The Linux kernel must support forwarding and bridged network traffic for Kubernetes networking to work correctly.
The following modules were loaded:
overlay
br_netfilter

The following sysctl settings were enabled:
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1

The most important routing setting is:
net.ipv4.ip_forward = 1

This allows Linux to forward packets between interfaces.
Without packet forwarding, traffic between Pod interfaces and other networks would not be routed correctly.
7. Cross-Node Pod Connectivity
Pod communication was tested using temporary BusyBox Pods.
One Pod was scheduled on the control plane and one on the worker.
Example Pod IPs:
Control Pod -> 10.244.0.6
Worker Pod  -> 10.244.1.5

Connectivity was tested using:
ping
traceroute

Example:
kubectl exec test-control -- traceroute 10.244.1.5

Observed path:
10.244.0.1
10.244.1.0
10.244.1.5

Reverse connectivity was also verified.
This confirmed:
Pod IP assignment       OK
Flannel overlay         OK
Cross-node routing      OK
Bidirectional traffic   OK

8. Service Network
The Kubernetes Service CIDR is:
10.96.0.0/12

Service IPs are virtual addresses used to provide stable access to Pods.
Examples from the lab:
Kubernetes API Service:
10.96.0.1

CoreDNS Service:
10.96.0.10

Juice Shop Service:
10.101.119.191

These addresses are not assigned directly to physical interfaces.
They are virtual Kubernetes Service addresses.
9. ClusterIP
Juice Shop is exposed internally through a ClusterIP Service.
Example:
Service:
10.101.119.191:3000

Backend Pod:
10.244.1.10:3000

The Service uses this selector:
app=juice-shop

which matches the Juice Shop Pod.
The Service endpoint was verified using:
kubectl describe svc juice-shop

Example:
Endpoints: 10.244.1.10:3000

The EndpointSlice also confirmed the backend:
kubectl get endpointslice \
  -l kubernetes.io/service-name=juice-shop

10. kube-proxy
kube-proxy runs on both nodes.
It helps implement Kubernetes Service networking.
The Service IP:
10.101.119.191

does not belong directly to the Juice Shop Pod.
Instead, Kubernetes networking redirects Service traffic toward the selected backend endpoint.
Conceptually:
Client Pod
    |
    v
10.101.119.191:3000
ClusterIP
    |
    v
kube-proxy / Service rules
    |
    v
10.244.1.10:3000
Juice Shop Pod

This allows Pod IPs to change without clients needing to know the new addresses.
11. CoreDNS
CoreDNS provides DNS resolution inside the Kubernetes cluster.
The DNS Service address is:
10.96.0.10

Pods automatically receive DNS configuration similar to:
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5

A Service named:
juice-shop

in namespace:
default

receives the full DNS name:
juice-shop.default.svc.cluster.local

This resolves to the Service ClusterIP:
10.101.119.191

DNS was verified using:
kubectl exec svc-test -- \
  nslookup juice-shop.default.svc.cluster.local

Expected result:
Name: juice-shop.default.svc.cluster.local
Address: 10.101.119.191

12. Internal Service Testing
The Juice Shop Service was tested from another Pod.
Direct ClusterIP test:
kubectl exec svc-test -- \
  wget -qO- http://10.101.119.191:3000

DNS-based test:
kubectl exec svc-test -- \
  wget -qO- http://juice-shop:3000

This validates the complete internal path:
Test Pod
   |
   v
CoreDNS
   |
   v
juice-shop Service
   |
   v
EndpointSlice
   |
   v
Juice Shop Pod

13. NodePort
The ingress-nginx controller is exposed using a NodePort Service.
The HTTP NodePort used in this lab is:
31401

The ingress controller Service maps:
NodePort 31401
     |
     v
Service port 80
     |
     v
ingress-nginx controller

This makes ingress-nginx reachable from the Windows host.
Example:
192.168.178.111:31401

NodePort was selected because this is a local kubeadm cluster with no cloud LoadBalancer implementation.
14. Ingress Networking
The Ingress resource routes HTTP traffic based on hostname and path.
Configured rule:
Host: juice.local
Path: /

Backend:
juice-shop:3000

The full traffic path is:
Windows Browser
192.168.178.1
      |
      | juice.local:31401
      v
Windows hosts file
      |
      | juice.local -> 192.168.178.111
      v
k8s-worker01
      |
      | NodePort 31401
      v
ingress-nginx Service
      |
      v
ingress-nginx Controller
      |
      v
Ingress Rule
      |
      v
juice-shop ClusterIP Service
      |
      v
Juice Shop Pod
10.244.1.10:3000

15. Windows Host Resolution
The Windows hosts file contains:
192.168.178.111 juice.local

This allows the browser to resolve:
juice.local

to the Kubernetes worker node.
The application is then accessed using:
http://juice.local:31401

16. UFW and Kubernetes Networking
UFW was enabled on the control-plane node to restrict Kubernetes API access.
Initial default policy:
deny incoming
allow outgoing
deny routed

The deny routed policy caused an important Kubernetes networking issue.
Pods running on the worker node could no longer reach CoreDNS Pods on the control plane.
Symptoms included:
nslookup juice-shop
connection timed out

and:
ping 10.244.0.7
100% packet loss

The problem was caused by UFW blocking forwarded Pod traffic.
17. UFW Fix
The issue was confirmed by temporarily disabling UFW.
After UFW was disabled, DNS immediately started working again.
Instead of leaving the firewall disabled, Pod routing was explicitly allowed:
sudo ufw route allow \
  from 10.244.0.0/16 \
  to 10.244.0.0/16

Flannel VXLAN traffic was also allowed:
sudo ufw allow \
  from 192.168.178.111 \
  to 192.168.178.110 \
  port 8472 \
  proto udp

The final firewall preserved:
Default incoming: DENY
Default routed: DENY

while adding only the required Kubernetes exceptions.
After the fix:
Cross-node Pod traffic   OK
CoreDNS                  OK
Service DNS              OK
UFW                      Active

18. API Server Networking
The Kubernetes API server listens on:
192.168.178.110:6443

Network access is restricted to approved sources.
Allowed clients:
192.168.178.1
Windows management host

192.168.178.111
Kubernetes worker node

Example UFW rules:
sudo ufw allow from 192.168.178.1 \
  to any port 6443 proto tcp

sudo ufw allow from 192.168.178.111 \
  to any port 6443 proto tcp

Connectivity from Windows was verified using:
Test-NetConnection 192.168.178.110 -Port 6443

Connectivity from the worker was verified using:
nc -zv 192.168.178.110 6443

and:
curl -k https://192.168.178.110:6443

The API returned:
403 Forbidden

for the unauthenticated curl request.
This confirmed that:
Network reachability  OK
TLS connection        OK
Authentication        not provided
Authorization         denied

19. Networking Verification Commands
Node addresses:
kubectl get nodes -o wide

Pod placement:
kubectl get pods -A -o wide

Pod CIDRs:
kubectl get nodes \
  -o custom-columns=NAME:.metadata.name,PODCIDR:.spec.podCIDR

Linux routes:
ip route

Network interfaces:
ip addr

Services:
kubectl get svc -A

Endpoints:
kubectl get endpointslice -A

CoreDNS:
kubectl get pods -n kube-system \
  -l k8s-app=kube-dns -o wide

Flannel:
kubectl get pods -n kube-flannel -o wide

kube-proxy:
kubectl get daemonset \
  -n kube-system kube-proxy

Ingress:
kubectl get ingress

Ingress controller:
kubectl get svc,pods \
  -n ingress-nginx -o wide

20. Final Networking Architecture
                    Windows Host
                   192.168.178.1
                          |
                          |
                 VMware VMnet8 NAT
                 192.168.178.0/24
                    /           \
                   /             \
                  v               v
         k8s-control          k8s-worker01
       192.168.178.110       192.168.178.111
              |                     |
              |                     |
        10.244.0.0/24         10.244.1.0/24
              |                     |
          CoreDNS                Juice Shop
       10.244.0.7/.8            10.244.1.10
              \                     /
               \                   /
                +--- Flannel -----+
                     VXLAN
                    UDP/8472

Service Network:
10.96.0.0/12

CoreDNS:
10.96.0.10

Kubernetes API:
10.96.0.1

Juice Shop Service:
10.101.119.191:3000

Ingress:
juice.local
      |
      v
192.168.178.111:31401
      |
      v
ingress-nginx
      |
      v
juice-shop:3000
      |
      v
10.244.1.10:3000
