## Overview

### Install

1. Install Longhorn.
1. Install Longhorn [upgrade-responder](https://github.com/longhorn/upgrade-responder) stack.
   ```bash
   ./install.sh 
   ```
   Sample output:
   ```shell
   secret/influxdb-creds created
   persistentvolumeclaim/influxdb created
   deployment.apps/influxdb created
   service/influxdb created
   Deployment influxdb is running.
   Cloning into 'upgrade-responder'...
   remote: Enumerating objects: 1077, done.
   remote: Counting objects: 100% (1076/1076), done.
   remote: Compressing objects: 100% (454/454), done.
   remote: Total 1077 (delta 573), reused 1049 (delta 565), pack-reused 1
   Receiving objects: 100% (1077/1077), 55.01 MiB | 18.10 MiB/s, done.
   Resolving deltas: 100% (573/573), done.
   Release "longhorn-upgrade-responder" does not exist. Installing it now.
   NAME: longhorn-upgrade-responder
   LAST DEPLOYED: Thu May 11 00:42:44 2023
   NAMESPACE: default
   STATUS: deployed
   REVISION: 1
   TEST SUITE: None
   NOTES:
   1. Get the Upgrade Responder server URL by running these commands:
     export POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/name=upgrade-responder,app.kubernetes.io/instance=longhorn-upgrade-responder" -o jsonpath="{.items[0].metadata.name}")
     kubectl port-forward $POD_NAME 8080:8314 --namespace default
     echo "Upgrade Responder server URL is http://127.0.0.1:8080"
   Deployment longhorn-upgrade-responder is running.
   persistentvolumeclaim/grafana-pvc created
   deployment.apps/grafana created
   service/grafana created
   Deployment grafana is running.
   
   [Upgrade Checker]
   URL       : http://longhorn-upgrade-responder.default.svc.cluster.local:8314/v1/checkupgrade
   
   [InfluxDB]
   URL       : http://influxdb.default.svc.cluster.local:8086
   Database  : longhorn_upgrade_responder
   Username  : root
   Password  : root
   
   [Grafana]
   Dashboard : http://1.2.3.4:30864
   Username  : admin
   Password  : admin
   ```
