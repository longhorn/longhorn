# Longhorn Example Grafana Dashboard

`longhorn-example-grafana-dashboard.json` is the "Longhorn Example" Grafana
dashboard, which is also published on grafana.com as
[dashboard 13032](https://grafana.com/grafana/dashboards/13032). It is kept in
this repository so it can be updated together with changes to the Longhorn
Prometheus metrics.

## Metric format

Since Longhorn v1.11.0 (longhorn/longhorn#10723), `longhorn_volume_state` and
`longhorn_volume_robustness` are exposed as one series per state, using a
`state` label and a `0`/`1` value, instead of a numeric enum:

```text
longhorn_volume_state{node="worker-2",volume="testvol",state="attached",...} 1
longhorn_volume_state{node="worker-2",volume="testvol",state="detached",...} 0
longhorn_volume_robustness{node="worker-2",volume="testvol",state="healthy",...} 1
longhorn_volume_robustness{node="worker-2",volume="testvol",state="degraded",...} 0
```

The dashboard in this directory selects states with the `state` label, for
example `count(longhorn_volume_robustness{state="degraded"}==1)`. It therefore
requires Longhorn v1.11.0 or later. Older revisions of the dashboard that
compare these metrics against numeric values (`==2`, `==3`, ...) show no data
or wrong counts on v1.11.0 or later.

## Import

1. Make sure Prometheus scrapes the `longhorn-backend` service on port `9500`.
2. In Grafana, go to **Dashboards > New > Import** and upload
   `longhorn-example-grafana-dashboard.json`.
3. Select the Prometheus data source when prompted.
