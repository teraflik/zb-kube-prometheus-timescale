local k = import 'ksonnet/ksonnet.beta.3/k.libsonnet';
local pvc = k.core.v1.persistentVolumeClaim;

local kp =
  (import 'kube-prometheus/kube-prometheus.libsonnet') +
  // enable kops specific config
  (import 'kube-prometheus/kube-prometheus-kops.libsonnet') + 
  // Strip limits on few components to decrease scrape time for large clusters
  (import 'kube-prometheus/kube-prometheus-managed-cluster.libsonnet') +
  // Uncomment the following imports to enable its patches
  // (import 'kube-prometheus/kube-prometheus-anti-affinity.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-managed-cluster.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-node-ports.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-static-etcd.libsonnet') +
  // (import 'kube-prometheus/kube-prometheus-thanos-sidecar.libsonnet') +
  {
    _config+:: {
      namespace: 'monitoring',
    },
    prometheus+:: {
      prometheus+: {
        // metadata+: {
        //   name: 'epimetheus',
        // },
        spec+: {
          replicas: 3,
          scrapeInterval: '10s',
          walCompression: true,
          storage: {
            volumeClaimTemplate:
              pvc.new() +
              pvc.mixin.spec.withAccessModes('ReadWriteOnce') +
              pvc.mixin.spec.resources.withRequests({storage: '10Gi'}) +
              pvc.mixin.spec.withStorageClassName('gp2'),
          },
          remoteWrite: [
            {
              url: 'http://localhost:9201/write'
            }
          ],
          remoteRead: [
            {
              url: 'http://localhost:9201/read',
              readRecent: true
            }
          ],
          initContainers: [
          {
            name: 'timescaledb-init',
            image: 'postgres',
            imagePullPolicy: 'IfNotPresent',
            env: [
              {
                name: 'PGHOST',
                value: 'timescale-db'
              },
              {
                name: 'PGPORT',
                value: '5432'
              },
              {
                name: 'PGDATABASE',
                value: 'epimetheus'
              },
              {
                name: 'PGUSER',
                value: 'postgres'
              },
              {
                name: 'PGPASSWORD',
                valueFrom: {
                  secretKeyRef: {
                    key: 'password',
                    name: 'postgres.timescale-db.credentials'
                  }
                }
              }
            ],
            command: [
              'bash'
            ],
            args: [
              "-c",
              "SECONDS=0; while ! psql -c 'SELECT NOW();'; do\n  test $SECONDS -gt 150 && exit 1;\n  echo 'Retrying in 5 seconds...';\n  sleep 5s;\ndone; psql -c 'CREATE EXTENSION IF NOT EXISTS pg_prometheus CASCADE;\n         CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;\n         GRANT ALL ON SCHEMA prometheus TO epimetheus;';"
            ]
          }],
          "containers": [{
            name: 'timescaledb-adapter',
            image: 'timescale/prometheus-postgresql-adapter:0.6.0',
            env: [
              {
                name: 'TIMESCALEDB_HOST',
                value: 'timescale-db'
              },
              {
                name: 'TIMESCALEDB_PORT',
                value: '5432'
              },
              {
                name: 'TIMESCALEDB_NAME',
                value: 'epimetheus'
              },
              {
                name: 'TIMESCALEDB_USER',
                value: 'epimetheus'
              },
              {
                name: 'TIMESCALEDB_PASSWORD',
                valueFrom: {
                  secretKeyRef: {
                    name: 'epimetheus.timescale-db.credentials',
                    key: 'password'
                  }
                }
              }
            ],
            args: [
              '-leader-election-pg-advisory-lock-id=1',
              '-leader-election-pg-advisory-lock-prometheus-timeout=15s',
              '-pg-host=$(TIMESCALEDB_HOST)',
              '-pg-port=$(TIMESCALEDB_PORT)',
              '-pg-database=$(TIMESCALEDB_NAME)',
              '-pg-user=$(TIMESCALEDB_USER)',
              '-pg-password=$(TIMESCALEDB_PASSWORD)',
              '-pg-prometheus-chunk-interval=24h'
            ],
            ports: [
              {
                name: 'http-storage',
                containerPort: 9201,
                protocol: 'TCP'
              }
            ],
            livenessProbe: {
              httpGet: {
                port: 'http-storage',
                path: '/healthz'
              },
              initialDelaySeconds: 20,
              failureThreshold: 3,
              periodSeconds: 10
            },
            resources: {
              requests: {
                cpu: '20m',
                memory: '100Mi'
              },
              limits: {
                cpu: '100m',
                memory: '500Mi'
              }
            }
          }],
        },
      },
    },
    alertmanager+:: {
      config: importstr 'alertmanager-config.yaml',
    },
  };

{ ['00namespace-' + name]: kp.kubePrometheus[name] for name in std.objectFields(kp.kubePrometheus) } +
{ ['0prometheus-operator-' + name]: kp.prometheusOperator[name] for name in std.objectFields(kp.prometheusOperator) } +
{ ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
{ ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
{ ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) } +
{ ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) }
