# Kubernetes Monitoring Recommendation

This document describes the monitoring approach recommended for the two-node Kubernetes lab.

The goal is to monitor:

1. Node health
2. Pod and container resource usage
3. Kubernetes object state
4. Application availability
5. Historical metrics and dashboards

The recommended stack is:

```text
Metrics Server
Prometheus
Grafana
kube-state-metrics
node_exporter

Each component has a different purpose.
1. Monitoring Architecture
Recommended architecture:
                   Kubernetes Cluster

        +-------------------------------+
        |                               |
        |      Kubernetes Objects       |
        | Pods / Deployments / Nodes    |
        |                               |
        +---------------+---------------+
                        |
                        v
               kube-state-metrics
                        |
                        v
                    Prometheus
                        |
                        v
                     Grafana


k8s-control -----------------> node_exporter
k8s-worker01 ----------------> node_exporter
                                  |
                                  v
                              Prometheus


Kubelet / Metrics APIs
        |
        v
   Metrics Server
        |
        v
kubectl top nodes
kubectl top pods

The stack can be divided into two purposes:
Metrics Server
→ lightweight current resource usage

Prometheus stack
→ historical monitoring and dashboards

2. Metrics Server
Metrics Server provides lightweight CPU and memory usage information for Kubernetes resources.
It collects resource metrics from the kubelets running on the nodes.
The main use case is:
kubectl top nodes

and:
kubectl top pods

Example output might look like:
NAME           CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
k8s-control    150m         7%     1200Mi          35%
k8s-worker01   220m         11%    1500Mi          28%

Metrics Server is useful for quickly answering questions such as:
Which node is using the most CPU?

Which Pod is consuming the most memory?

Is a Pod approaching its resource limit?

Metrics Server does not provide long-term historical storage.
It is mainly used for current resource metrics.
3. Prometheus
Prometheus is the main monitoring and time-series metrics collection system recommended for the cluster.
Prometheus:
- scrapes metrics endpoints
- stores time-series data
- allows querying using PromQL
- supports alerting
- integrates with Grafana
Prometheus can collect metrics from:
Kubernetes nodes
Pods
Applications
kube-state-metrics
node_exporter
Kubernetes components

Conceptually:
Metrics Endpoint
      |
      | scrape
      v
Prometheus
      |
      v
Time-Series Database

This allows metrics to be stored over time.
For example:
CPU usage now
CPU usage 1 hour ago
CPU usage yesterday

This is one of the main differences between Prometheus and Metrics Server.
4. Grafana
Grafana provides visualization and dashboards.
Prometheus stores the metrics.
Grafana reads those metrics and presents them visually.
Conceptually:
Prometheus
    |
    | PromQL queries
    v
Grafana
    |
    v
Dashboards

Grafana dashboards can display:
- CPU usage
- memory usage
- filesystem usage
- network usage
- Pod status
- node health
- container restarts
- Deployment replicas
- application availability
Grafana makes it easier to identify trends and problems without manually running CLI commands.
5. node_exporter
node_exporter provides Linux operating-system and hardware metrics.
It should run on each Kubernetes node.
For this cluster:
k8s-control
    |
    +--> node_exporter

k8s-worker01
    |
    +--> node_exporter

It exposes metrics such as:
CPU
Memory
Disk
Filesystem
Network interfaces
Load average
System uptime

Example questions node_exporter can help answer:
Is the control-plane node running out of disk space?

Is worker CPU usage high?

Is memory pressure increasing?

Is a network interface dropping packets?

This is especially useful because Kubernetes workloads still depend on the health of the underlying Linux nodes.
6. kube-state-metrics
kube-state-metrics exposes information about the state of Kubernetes objects.
It does not mainly measure CPU or memory.
Instead, it converts Kubernetes object state into Prometheus metrics.
Examples include:
Number of desired Deployment replicas

Number of available replicas

Pod phases

Node conditions

Container restart counts

Job status

PersistentVolume status

Conceptually:
Kubernetes API
      |
      v
kube-state-metrics
      |
      v
Prometheus

This allows Prometheus to monitor the logical state of Kubernetes resources.
7. node_exporter vs kube-state-metrics
These components monitor different layers.
node_exporter
Monitors:
Linux machine

Examples:
CPU
RAM
Disk
Network
Filesystem

kube-state-metrics
Monitors:
Kubernetes object state

Examples:
Deployment replicas
Pod status
Node Ready status
Job state
Container restarts

A useful comparison:
Component	Monitors
node_exporter	Linux node
kube-state-metrics	Kubernetes objects
Metrics Server	Current Kubernetes CPU/memory
Prometheus	Collects and stores metrics
Grafana	Visualizes metrics


8. Monitoring the Control Plane
The control-plane node runs critical components:
kube-apiserver
etcd
kube-scheduler
kube-controller-manager
kubelet
containerd

Important metrics to monitor include:
CPU usage
Memory usage
Disk usage
API server availability
etcd health
Container restarts
Node Ready status

The control-plane node is especially important because failure of its core services affects cluster management.
9. Monitoring the Worker Node
The worker node hosts the application workloads.
In this lab it runs components including:
Juice Shop
ingress-nginx
Flannel
kube-proxy
kubelet
containerd

Important metrics include:
CPU usage
Memory usage
Disk usage
Pod restarts
Container status
Network usage
Node Ready status

Application workload resource usage should also be monitored.
10. Monitoring Juice Shop
The Juice Shop Deployment should be monitored at both Kubernetes and application levels.
Kubernetes-level monitoring includes:
Pod status
Pod restarts
Deployment replica availability
CPU usage
Memory usage
Node placement

Example commands:
kubectl get deployment juice-shop
kubectl get pods -o wide
kubectl describe deployment juice-shop

Prometheus and Grafana could provide historical visibility into these metrics.
11. Monitoring ingress-nginx
The ingress controller is an important part of the application path.
The traffic flow depends on it:
External User
     |
     v
NodePort
     |
     v
ingress-nginx
     |
     v
Ingress
     |
     v
Juice Shop Service

Important ingress metrics can include:
Request count
Request rate
HTTP status codes
Response latency
Connection count
Ingress controller health

These metrics are useful for identifying application access problems.
12. Monitoring CoreDNS
CoreDNS is required for Kubernetes Service discovery.
Important things to monitor include:
CoreDNS Pod availability
DNS request rate
DNS errors
DNS latency
Pod restarts

CoreDNS failure can cause applications to fail even when the actual destination Service is healthy.
This lab already demonstrated this dependency when UFW blocked routed Pod traffic and DNS queries started timing out.
13. Monitoring Flannel Networking
Flannel provides cross-node Pod networking.
Important indicators include:
Flannel Pod status
Node connectivity
VXLAN connectivity
Pod-to-Pod communication

The Flannel DaemonSet can be checked using:
kubectl get pods -n kube-flannel -o wide

Expected:
One Flannel Pod per Kubernetes node

If a Flannel Pod fails, Pod networking on that node may become unavailable.
14. Monitoring Commands
Even without a full monitoring stack, Kubernetes provides useful CLI commands.
Check nodes:
kubectl get nodes

Detailed node information:
kubectl describe node k8s-control
kubectl describe node k8s-worker01

Check all Pods:
kubectl get pods -A

Check Pod restarts:
kubectl get pods -A -o wide

Check application logs:
kubectl logs deployment/juice-shop

Check ingress controller logs:
kubectl logs deployment/ingress-nginx-controller \
  -n ingress-nginx

Check events:
kubectl get events -A \
  --sort-by=.lastTimestamp

Check Linux resources:
free -h
df -h
top

15. Metrics Server Recommendation
Metrics Server is recommended for this cluster because it provides an easy way to view current Kubernetes resource consumption.
After installation, useful commands would include:
kubectl top nodes

and:
kubectl top pods -A

This is useful for quick operational checks.
However, Metrics Server alone is not enough for full monitoring because it does not provide long-term historical data or dashboards.
16. Prometheus Recommendation
Prometheus is recommended as the main metrics collection platform.
It can collect data from:
node_exporter
kube-state-metrics
Kubernetes components
application metrics
ingress-nginx

Prometheus provides:
historical metrics
querying
alerting
integration with Grafana

This makes it suitable for deeper cluster observability.
17. Grafana Recommendation
Grafana is recommended for visualization.
Useful dashboards could include:
Kubernetes cluster overview

Node resource usage

Pod resource usage

Ingress traffic

CoreDNS health

Application workload health

Grafana would use Prometheus as its data source.
18. Suggested Production Monitoring Stack
For a larger or production-like cluster, the recommended architecture would be:
                Kubernetes Cluster

Nodes
  |
  +------ node_exporter ----------------+
                                        |
Kubernetes API                          |
  |                                     |
  +------ kube-state-metrics -----------+
                                        |
Applications                            |
  |                                     |
  +------ metrics endpoints ------------+
                                        |
Ingress Controller                      |
  |                                     |
  +------ ingress metrics --------------+
                                        |
                                        v
                                   Prometheus
                                        |
                           +------------+------------+
                           |                         |
                           v                         v
                        Grafana                 Alertmanager

Alertmanager can later be used for notifications.
Possible destinations include:
Email
Slack
PagerDuty
Webhook

19. Example Alerts
Useful alerts could include:
Node Not Ready
Node Ready condition becomes false

High CPU Usage
Node CPU > 80%

High Memory Usage
Node memory > 85%

Disk Space
Filesystem usage > 80%

Pod Restarting
Container restart count increasing

Deployment Unavailable
Available replicas < desired replicas

CoreDNS Failure
CoreDNS Pods unavailable

Ingress Failure
High HTTP 5xx error rate

20. Why This Stack Was Chosen
The recommended stack separates responsibilities clearly.
Metrics Server
→ quick Kubernetes resource usage

node_exporter
→ Linux node metrics

kube-state-metrics
→ Kubernetes object state

Prometheus
→ metric collection and historical storage

Grafana
→ dashboards and visualization

Together they provide visibility across:
Infrastructure
Kubernetes
Applications
Networking

21. Recommended Monitoring Stack for This Lab
For this specific lab, the recommendation is:
Metrics Server
Prometheus
Grafana
kube-state-metrics
node_exporter

This would provide:
Current resource usage
Historical metrics
Node monitoring
Kubernetes object monitoring
Application monitoring
Dashboards
