# ☸️ Kubernetes & AWS EKS Networking Architecture Notes

### 1. The Core Execution Engine (The Worker Node)
* **Kubelet:** The primary agent running on every worker node. It functions as the "ship captain" for that machine. It registers the node with the control plane, monitors container health (probes), and instructs the container runtime (`containerd`/Docker) to start or stop pods based on instructions (PodSpecs) from the API Server.
* **The Control Plane Loop:** The API Server acts as a passive database/gatekeeper. The **Kubelet** actively pushes health data and **Node Leases** (heartbeats every 10 seconds) to the API Server. The **Node Lifecycle Controller** monitors these timestamps and marks a node `NotReady` if a lease expires (default 40s).

### 2. The Matchmaker (Kube-Scheduler)
* **Role & Location:** Runs strictly on the **Control Plane**. It assigns newly created, unassigned pods to the optimal worker node. If it stops running, new pods stay stuck in a `Pending` state.
* **EKS Specifics:** On AWS EKS, the scheduler runs in a secure, AWS-managed account. You **cannot** see the scheduler pod using `kubectl get pods`. To see its behavior, you must enable EKS Control Plane Logging via **AWS CloudWatch** or read system events using `kubectl get events`.
* **The 2-Phase Algorithm:**
    1. **Filtering (Predicates):** Knocks out nodes that fail hard requirements (insufficient CPU/RAM, port clashes, taints/tolerations).
    2. **Scoring (Priorities):** Ranks remaining nodes based on criteria like resource balance, image locality (is the docker image already downloaded?), and pod anti-affinity.

### 3. The EKS Core Network Add-ons (`kube-system`)
When running `kubectl get pods -n kube-system` on EKS, you manage the data plane utilities running on your worker nodes:
* **`aws-node` (DaemonSet):** The AWS VPC CNI plugin. It runs on *every* node and allocates **real, native AWS VPC IP addresses** directly to your pods from your VPC subnets.
* **`kube-proxy` (DaemonSet):** Runs on *every* node. It is the networking "muscle" that watches the API Server for Service changes and programs local network routing rules directly into the worker node's **Linux kernel** (`iptables` or `IPVS`).
* **`coredns` (Deployment):** The internal cluster phone book. Usually deploys as 2 replicas spread across available worker nodes. It automatically resolves readable service domain names into target IP addresses.

### 4. Kubernetes Services & Internal Networking
* **The Ephemeral Pod Problem:** Pods are short-lived. Every time they regenerate, `aws-node` gives them a brand new AWS IP address. A **Service** acts as a permanent umbrella front-door for these pods using **Labels and Selectors**.
* **The Core Rule:** Every standard service (like `ClusterIP`) gets **two permanent things** simultaneously:
    1. A constant virtual IP address.
    2. A default internal DNS name (`<service>.<namespace>.svc.cluster.local`) managed by CoreDNS.
* **Decentralized Routing:** When a pod calls a Service IP, the traffic **never leaves the node** to go to an external physical load balancer. The host machine's Linux kernel (programmed by `kube-proxy`) intercepts the packet locally, rewrites the destination using NAT (Network Address Translation) to a real, healthy target Pod VPC IP, and fires it over the AWS network.

### 5. Service Types Compared
* **`ClusterIP`:** Internal access only. It creates a completely virtual cluster IP that does **not** exist on your AWS VPC subnets. It is unrouteable from outside the cluster.
* **`NodePort`:** External access via worker nodes. It is a standard `ClusterIP` service with an **extra superpower**: it opens a matching high-numbered port (`30000-32767`) on the physical AWS IPs of all worker nodes. 
    * *Note:* Even if a service is a `NodePort`, it **still gets a ClusterIP and a local DNS name** for internal pod-to-pod communication.
* **`LoadBalancer` (EKS Special):** Spins up a native AWS Load Balancer (ALB/NLB) in your cloud account which routes external internet traffic into the cluster via the under-the-hood `NodePort` layer.

### 6. Integrating External Systems (Manual Endpoints)
* **`EndpointSlice`:** The backend network directory of a Service. 
* **Hybrid Architecture Pattern:** By creating a standard Kubernetes Service *without a pod selector*, and manually writing a matching `EndpointSlice` file linking to the Service name (`kubernetes.io/service-name`), you can cleanly route internal cluster traffic to an **external system** (like a Prefect server or database running on a separate standalone EC2 instance) using a native, clean Kubernetes internal DNS name.


# 📊 Kubernetes Resource Management: Requests vs. Limits

### 1. Core Definitions
*   **Resource Requests (The Guaranteed Minimum):** The absolute minimum amount of CPU or memory a container is guaranteed to receive. 
    *   *Scheduler Role:* The `kube-scheduler` looks **only** at Requests when choosing which node a pod can fit on. If a node doesn't have enough free requested space, the pod stays `Pending`.
*   **Resource Limits (The Hard Ceiling):** The absolute maximum amount of CPU or memory a container is permitted to consume. It prevents a single misbehaving application from starving other processes on the host.

### 2. How Violations Are Enforced (Via Linux Cgroups)
Kubernetes treats memory and CPU violations completely differently based on how hardware works:

#### Memory (RAM) -> Enforcement: The OOM Killer (Death Penalty)
Memory is an absolute asset; running out crashes the host machine.
*   **The Executioner:** The container's host **Linux Kernel (OOM Killer)** monitors memory via `cgroups`. 
*   **The Action:** The millisecond a container attempts to allocate memory over its designated **Limit**, the Linux Kernel steps in and kills the process instantly using a `SIGKILL` signal.
*   **The Result:** The container terminates immediately with **Exit Code 137**.

#### CPU -> Enforcement: Throttling (Speed Governor)
CPU is a renewable asset measured in time slices; running out just slows the machine down.
*   **The Executioner:** The host **Linux Kernel** uses `cgroups` to restrict access to CPU time slices once the limit is touched.
*   **The Action:** The container is **never killed**. Instead, it is artificially slowed down (starved of CPU cycles).
*   **The Result:** The application remains running but experiences severe latency spikes, slow response times, or timeouts.

### 3. Kubelet Reporting back to the API Server
The Kubelet treats these two enforcement events entirely differently when updating the central cluster:

| Resource Exceeded | Container Dies? | Reported to API Server? | Where to Find/Debug |
| :--- | :--- | :--- | :--- |
| **Memory (`OOMKilled`)** | **Yes** 💀 | **Yes** | Visible in `kubectl describe pod` under the container's `Last State: OOMKilled` with Exit Code 137. |
| **CPU (Throttling)** | **No** 🐌 | **No** | **Invisible** in `kubectl`. Pod status shows `Running`. Must be monitored using metrics tools like **Prometheus** or **AWS CloudWatch Container Insights**. |

### 4. Quality of Service (QoS) Classes
Kubernetes automatically assigns an architectural priority tier to your pods depending on your Resource configurations. If a node experiences extreme resource pressure, it uses these classes to decide who to evict first:

1.  **Guaranteed (Highest Priority):** You set your **Requests exactly equal to your Limits** (e.g., Request 1Gi, Limit 1Gi). Safe from eviction unless the host machine completely fails.
2.  **Burstable (Medium Priority):** Your **Request is lower than your Limit** (e.g., Request 256Mi, Limit 512Mi). Allowed to scale up if space exists, but will be evicted first if the node runs low on resources.
3.  **BestEffort (Lowest Priority):** You **do not define any requests or limits**. Takes the leftover scraps of the node. These are the absolute first pods killed/evicted when the node gets busy.

# 🔄 The End-to-End Pod Lifecycle & Network Timeline

### 🎬 Chronological Stage-by-Stage Breakdown

#### Phase 1: Creation & Scheduling (`Pending`)
*   **User / Controller Manager:** Submits the Pod manifest to the **API Server** (the database).
*   **Kube-Scheduler:** Watches the API Server, filters/scores nodes, and assigns the Pod to a specific worker node. 

#### Phase 2: Environment Prep & Network Setup (`Pending`)
*   **Kubelet (on the target node):** Detects the assignment and coordinates with the container runtime to build the environment.
*   **`aws-node` (AWS VPC CNI Plugin):** Intercepts the request *before* containers start. It claims a **real, private AWS VPC IP address** from your AWS subnet and binds it to the Pod's network space.
*   **Kubelet:** Writes this new VPC IP back to the API Server.

#### Phase 3: Container Initialization (`Pending` ──> `Running`)
*   **Kubelet:** Pulls the required container images over the network.
*   **Container Runtime (`containerd`/Docker):** Launches any `Init Containers` sequentially. They must successfully exit (`exit 0`).
*   **Container Runtime:** Spins up the main application containers, which bind to their ports using the IP provided by `aws-node`.

#### Phase 4: Traffic Integration (`Running`)
*   **Kubelet:** Runs the configured **Startup and Readiness Probes** against the application.
*   **API Server / Control Plane:** The moment the Readiness Probe passes, it updates the central **`EndpointSlice`** list with the Pod's VPC IP.
*   **CoreDNS:** Maintains the service name to ClusterIP mapping.
*   **`kube-proxy` (On every node):** Detects the updated `EndpointSlice` via the API Server and rewrites local **Linux kernel (`cgroups`/`iptables`)** routing rules cluster-wide.
*   *Result:* Live traffic begins flowing to the Pod.

#### Phase 5: The Graceful Teardown (`Terminating`)
*   **API Server:** Initiates deletion and immediately drops the Pod’s IP from the Service's **`EndpointSlice`**.
*   **`kube-proxy` (On every node):** Instantly updates host kernels to **stop routing new traffic** to this Pod.
*   **Kubelet:** Sends a **`SIGTERM`** signal to the application container.
*   **The Application:** Uses the grace period (default 30s) to safely finish processing active network requests and close database connections.
*   **Kubelet / Linux Kernel:** If the app is still alive after 30s, the Kubelet sends a **`SIGKILL`**. The kernel shuts down the process instantly.
*   **`aws-node`:** Releases the VPC IP back into the AWS subnet pool to be recycled.

---

### 🎛️ Actor Cheat Sheet

*   **API Server:** The passive database holding the status of everything.
*   **Kube-Scheduler:** The matchmaker assigning Pods to Nodes.
*   **Kubelet:** The node agent pulling images, monitoring health probes, and handling restarts.
*   **Linux Kernel (`cgroups`):** The underlying host mechanism enforcing memory limits (`OOMKilled`) and CPU limits (throttling).
*   **`aws-node`:** The AWS utility provisioning and recycling real VPC IP addresses.
*   **CoreDNS:** The internal phone book translating Service names to ClusterIPs.
*   **`kube-proxy`:** The router updating the host's Linux kernel to direct traffic from Services to Pods.

# 🗺️ Kubernetes External Routing: Ingress & AWS Load Balancing

### 1. Ingress Core Components
An Ingress functions as the smart front door or traffic receptionist for the entire cluster. It maps public HTTP/HTTPS traffic from the outside world directly to internal cluster Services based on domain names or URL paths (e.g., `/api` vs `/static`). It is split into two components:
*   **The Ingress Resource:** A declarative YAML rulebook defining your routing paths. It holds no software footprint on its own.
*   **The Ingress Controller:** The actual software daemon (reverse proxy) running on your worker nodes that actively reads the rulebook and physically routes the incoming packets.

---

### 2. Architecture Comparison: AWS ALB vs. NGINX Ingress

When deploying on AWS EKS, the choice between utilizing an **AWS Application Load Balancer (ALB)** or an **NGINX Ingress Controller** determines how traffic flows into your worker nodes.

#### Option A: AWS Load Balancer Controller (ALB Mode)
This controller maps your Ingress resource directly onto a physical AWS Application Load Balancer resource running out in your cloud account.
*   **The Ingress Class:** Set via `ingressClassName: alb`.
*   **How it Routes (IP Mode):** It evaluates your target Service's `EndpointSlice` list and automatically registers the **native Pod VPC IPs** (provided by `aws-node`) straight into the AWS ALB Target Group. This completely bypasses worker node ports, making it highly efficient.
*   **Pros:** Out-of-the-box integration with AWS WAF, AWS Shield, and AWS Certificate Manager (ACM) certificates with zero overhead on your worker nodes' CPU/RAM.
*   **Cons:** Cost scale issues (AWS charges per ALB; a separate Ingress manifest per microservice spins up a separate costly ALB). Configuration shifts can take up to a minute due to external cloud API propagation delays.

#### Option B: NGINX Ingress Controller (Multi-Tenant Pattern)
This deployment places an NGINX reverse-proxy application *inside* your cluster. You place a single AWS Load Balancer in front of NGINX to tunnel raw traffic inside. 
*   **The Ingress Class:** Set via `ingressClassName: nginx`.
*   **How it Routes (Host-Header Routing):** The external AWS load balancer does no smart pathing; it blindly dumps all traffic into the NGINX pods. NGINX reads your Ingress rules internally in memory, inspects the HTTP **Host Header** (e.g., `client1.example.org`, `client2.example.org`), and forwards the traffic to the correct multi-tenant backend pods (like 20+ separate Superset instances).
*   **Pros:** Highly cost-effective (you only pay for one single AWS load balancer for hundreds of microservices/subdomains). Routing rule updates take sub-second execution speeds. Features advanced traffic shaping like deep rate-limiting and custom regex paths.
*   **Cons:** Consumes your paid node resources (decryption and traffic inspection happen directly inside your cluster). Adds a "double network hop" (External LB ──> NGINX Pod ──> App Pod).

---

### 3. Case Study: Analyzing an EKS Ingress Manifest

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-airbyte
  namespace: monitoring
  annotations:
    alb.ingress.kubernetes.io/load-balancer-name: dalgo-prod-grafana-alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/subnets: subnet-072059f8c76371eea,subnet-0181641712cc0826a
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/healthcheck-path: /api/health
spec:
  ingressClassName: alb
  rules:
    - host: grafana-airbyte.dalgo.org
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kube-prometheus-stack-1739860793-grafana
                port:
                  number: 80
```
#### Why this is strictly an AWS Managed ALB (Not NGINX):
1.  **`ingressClassName: alb`** explicitly commands the AWS Load Balancer Controller to provision a cloud resource.
2.  **`alb.ingress.kubernetes.io/*`** annotations are proprietary parameters understood only by the AWS cloud controller to define the name, public schema, subnet IDs, and SSL redirects on the cloud infrastructure.
3.  **`target-type: ip`** forces the controller into IP Mode, mapping pod endpoints directly into the physical ALB targets.

---

### 4. The Golden Rule of Cloud Balancing: Managing Configuration Drift

When managing auto-provisioned cloud balancers (whether an ALB built via Ingress annotations, or a CLB/NLB built via an NGINX `type: LoadBalancer` Service):

*   **⚠️ NEVER change settings manually in the AWS Console:** The Ingress controller and Service manager run continuous reconciliation event loops. If you modify a security group, change a timeout, or swap out a listener via the AWS Console UI, the Kubernetes controller will flag it as **Configuration Drift** and automatically overwrite your manual cloud changes back to the cluster manifest's definition within minutes.
*   **✅ The Kubernetes Way (Annotations):** To make infrastructure adjustments, you must write changes directly into your Kubernetes YAML files as annotations.

---

### 5. Why You Must Force a Network Load Balancer (NLB) Over Classic (CLB)

By default, when you use `type: LoadBalancer` on EKS for NGINX without specifying a type, Kubernetes uses a legacy cloud driver that provisions an outdated **Classic Load Balancer (CLB)**. Adding the annotation `service.beta.kubernetes.io/aws-load-balancer-type: "nlb"` forces a modern **Network Load Balancer (NLB)**, unlocking four major architectural advantages:

#### 1. Overcoming Legacy Tech & Future-Proofing
The CLB is previous-generation technology built back in 2010. AWS strongly discourages using CLBs for modern cloud infrastructure and actively phases them out of their ecosystem. No new features are added to CLBs, and they are less cost-effective over time compared to the optimized resource-unit pricing models of modern v2 load balancers (`ELBv2` / NLBs).

#### 2. True Client Source IP Preservation
In multi-tenant environments (e.g., 20+ clients on separate subdomains), knowing exactly who is connecting is vital for security auditing and logging.
*   **The CLB Flaw:** The CLB completely proxies the connection, replacing the client’s real source IP with its own internal balancer IP. Reclaiming the true IP requires configuring complex `X-Forwarded-For` HTTP header parsing.
*   **The NLB Advantage:** Operating at Layer 4 (the network packet level), an NLB tunnels traffic cleanly while **preserving the original client source IP completely intact**. Your NGINX pods can natively view, log, or firewall the client’s true external IP address right out of the box.

#### 3. Flawless Handling of Sudden Traffic Spikes
Heavy business analytics applications (like Apache Superset dashboards) face heavy multi-user traffic surges (e.g., first thing Monday morning when business teams log in).
*   **The CLB Flaw:** CLBs scale up slowly. A sudden spike can saturate the balancer, dropping user connections while it takes minutes to "pre-warm" its backends.
*   **The NLB Advantage:** The NLB is built for extreme throughput and ultra-low latency. It handles **millions of requests per second instantly**, scaling to traffic spikes with zero lag or pre-warming requirements.

#### 4. Native Support for Static/Elastic IPs
*   **The CLB Flaw:** A CLB's underlying IP addresses change constantly as AWS manages the cloud network fabric. It can only be targeted via its long, dynamic AWS DNS name.
*   **The NLB Advantage:** An NLB allows you to bind **static, unchanging AWS Elastic IPs** directly to the balancer interface across your availability zones. If enterprise clients have rigid corporate firewall constraints demanding a fixed list of static IP addresses to whitelist, you **must** use an NLB.

---

### 📝 Final Implementation Manifest: NGINX NLB + ACM Wildcard SSL Setup

If your NGINX pods are not struggling with CPU, you can choose to manage certificates inside the cluster via `cert-manager`. However, if you want to offload the SSL mathematical decryption entirely to AWS hardware and leverage a wildcard certificate (`*.example.org`), use this optimized NGINX Service configuration:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  annotations:
    # 1. Force AWS to provision a Network Load Balancer (NLB) instead of a Classic LB
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    
    # 2. Securely attach your AWS Certificate Manager Wildcard SSL Certificate to the external balancer
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:us-east-1:123456789012:certificate/your-wildcard-id"
    
    # 3. Specify which incoming ports should act as secure SSL entryways
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"

    # 4. Tell the NLB to send decrypted, plain HTTP traffic to your NGINX pods on Port 80
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "http"
spec:
  type: LoadBalancer
  ports:
    - name: http
      port: 80
      targetPort: http
    - name: https
      port: 443
      targetPort: https
```
