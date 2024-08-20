#/bin/bash
## bash runner script to execute k6 tests then store test results and capture resource metrics
## Usage:
## ./bash-runner.sh $COUNT $CLUSTER $CONTEXT $KUBECONFIG

#set kubeconfig && context
export CONTEXT=default && export KUBECONFIG=/Users/mspencer/Desktop/local.yaml

#Clear monitoring data
kubectl rollout restart statefulset -n cattle-monitoring-system prometheus-rancher-monitoring-prometheus

#Wait for deployment to stabilize, wait for 5min for metrics to normalize
sleep 360

#run test on upstream
k6 run -e VUS=10 -e PER_VU_ITERATIONS=30 -e BASEURL=https://ms.qa.rancher.space -e USERNAME=admin -e PASSWORD=uzqhMyPbo9oQiP7S -e CLUSTER=c-m-tt9pzmwl ./load_steve_new_pagination.js --summary-time-unit="ms" --summary-trend-stats="avg,min,med,max,p(90),p(99.9),p(99.99),count" > ../docs/vai-qa/3000_configmaps_load_steve_new_pagination_vai_on_c-m-tt9pzmwl.txt

#collect monitoring metrics, set kubeconfig, wait post-test for metrics to normalize
sleep 360

#start mimir pod && collect metrics

kubectl -n cattle-monitoring-system run mimirtool -ti --image=grafana/mimirtool --command -- mimirtool remote-read export --tsdb-path ./prometheus-export --address http://rancher-monitoring-prometheus:9090 --remote-read-path /api/v1/read --from=2024-05-01T00:00:00Z --selector '{__name__!=""}' 

kubectl exec -n cattle-monitoring-system mimirtool -- tar zcf /tmp/prometheus-export.tar.gz ./prometheus-export

kubectl -n cattle-monitoring-system cp mimirtool:/tmp/prometheus-export.tar.gz ./prometheus-export.tar.gz




kubectl -n cattle-monitoring-system run mimirtool --image=grafana/mimirtool --command -- mimirtool remote-read export --tsdb-path ./prometheus-export --address http://rancher-monitoring-prometheus:9090 --remote-read-path /api/v1/read --from=2024-05-01T00:00:00Z --selector '{__name__!=""}'  

kubectl exec -n cattle-monitoring-system mimirtool -- tar zcf /tmp/prometheus-export.tar.gz ./prometheus-export

kubectl -n cattle-monitoring-system cp mimirtool:/tmp/prometheus-export.tar.gz ./prometheus-export.tar.gz

