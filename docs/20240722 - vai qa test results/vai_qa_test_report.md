# Vai QA Testing Results (WiP)

### Setup

Local/Upstream -> 3 Nodes AWS t3a.xlarge (12 cores/48GB RAM)
Downstream -> 3 Nodes AWS t3a.xlarge (12 cores/48GB RAM)

rancher version: Rancher 2.9.0-alpha7 (vai patch)
added ENV VARs: CATTLE_PROMETHEUS_METRICS = true

k8s version: RKE2 - v1.26.9+rke2r1 (upstream), k3s - v1.26.8+k3s1 (downstream)
charts installed: Rancher Monitoring


### Testing

Validation goals:
  - **~65%-80% speedup** observed when using k8s-based pagination (`limit`/`continue`, currently used by the [dashboard](https://github.com/rancher/dashboard/) UI)
  - **~25%-66% speedup** observed when using the new Steve-cached pagination (`page`/`pagesize`)


#### Steps for testing:
**Environment:**
1) Bring up upstream cluster
2) Ensure forced etcd storage (all nodes have all roles)
3) Bring up & import downstream cluster
4) Ensure forced etcd storage (all nodes have all roles)
Tools: Dartboard/Terraform/Corral

**Rancher Setup:**
1. Create xxxxx configmaps on both clusters
2. Set CATTLE_PROMETHEUS_METRICS=true
3. Install monitoring upstream & downstream
Tools: bash/k6

**Process for testing and indepndent metrics capture:**
1. Run steve_k8s test on local cluster, capture stdout
2. Capture metrics with mimirtool
3. Repeat for downstream
4. Redeploy prometheus (clear data)
5. Run steve_new test on local cluster, capture stdout
6. Capture metrics with mimirtool
7. Repeat for downstream
8. Redeploy prometheus (clear data)
9. Enable vai
10. Repeate for local and downstream
Tools: bash/k6/mimirtool


Test Parameters:
`-e VUS=10 -e PER_VU_ITERATIONS=30 --summary-time-unit="ms" --summary-trend-stats="avg,min,med,max,p(90),p(99.9),p(99.99),count"`

Number of additional configmaps: `1000`, `5000`(wip), `9000`(wip)



| Cluster      | Test | VAI | http_req_duration | # of configmaps |
| ----------- | ----------- | ----------- | ----------- | ----------- |
| local      | k8s       | off | 746.65ms  | 1000 |
| local      | k8s       | on | 1127.90ms* | 1000 |
| local      | new       | off | 3018.40ms  | 1000 |
| local      | new       | on | `1081.51ms` | 1000 |
| downstream      | k8s       | off | 763.29ms | 1000 |
| downstream      | k8s       | on | 1676.68ms* | 1000 |
| downstream      | new       | off | 2667.16ms  | 1000 |
| downstream      | new       | on | `1656.60ms` | 1000 |


Viewing cluster metrics on 9090: (use date range 7/22-723)
```
tar xf prometheus-export.tar.gz
```
```
docker run --rm -u "$(id -u)" -ti -p 9090:9090 -v $PWD/prometheus-export:/prometheus rancher/mirrored-prometheus-prometheus:v2.42.0 --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=1y --config.file=/dev/null
```
Viewing another set of cluster metrics on 9091: ( add `--web.enable-admin-api --web.listen-address=:9091`)
```
docker run --rm -u "$(id -u)" -ti -p 9090:9091 -v $PWD/prometheus-export2:/prometheus rancher/mirrored-prometheus-prometheus:v2.42.0 --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=1y --config.file=/dev/null --web.enable-admin-api --web.listen-address=:9091
``` 