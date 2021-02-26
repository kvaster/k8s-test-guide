# Postgresql

Установка HA кластера postgresql на базе zolando оператора: https://github.com/zalando/postgres-operator.

## Устанавливаем оператор

TODO: посмотреть как создавать оператор в отдельном namespace

Оператор будем ставить с помощью helm'а. Для этого создадим наши кастомные `values.yml`:

```
configKubernetes:
  enable_pod_antiaffinity: true

#configGeneral:
#  repair_period: 5m
#  resync_period: 10m
```

Оператор рекомендуется ставить в CRD режиме вместо ConfigMaps:

```
helm install postgres-operator ./charts/postgres-operator -f ./charts/postgres-operator/values-crd.yaml -f values.yml
```

Для визуализации кластеров можно поставить UI:

```
helm install postgres-operator-ui ./charts/postgres-operator-ui
```

Добавляем тестовый кластер:

```
kind: "postgresql"
apiVersion: "acid.zalan.do/v1"

metadata:
  name: "acid-pg-main"
  namespace: "default"

spec:
  teamId: "acid"
  postgresql:
    version: "13"
    parameters:
      max_connections: "16384"
      # shared_buffers: "8GB"
      # temp_buffers: "512MB"
      # work_mem: "64MB"
      # maintenance_work_mem: "1GB"
      # max_stack_depth: "6MB"
      # max_files_per_process: "32768"
      # effective_io_concurrency: "2"
      # fsync: "off"
      # synchronous_commit: "off"
      # full_page_writes: "off"
      # max_wal_size: "12GB"
      # effective_cache_size: "32GB"
      # jit: "on"
      # log_temp_files: "0"
      # log_timezone: 'Europe/Minsk'
      # timezone: 'Europe/Minsk'
  numberOfInstances: 3
  users:
    dbadmin:
    - superuser
    - createdb
  databases:
    testdb: dbadmin
  volume:
    size: 1Gi
    storageClass: fast-disks
  enableMasterLoadBalancer: false
  enableReplicaLoadBalancer: false
  resources:
    requests:
      cpu: 100m
      memory: 100Mi
    limits:
      cpu: 500m
      memory: 500Mi
```

Находим IP нашего сервиса, добываем пароль и проверяем:

```
export PGPASSWORD=$(kubectl get secret dbadmin.acid-pg-main.credentials.postgresql.acid.zalan.do -o 'jsonpath={.data.password}' | base64 -d)
export PGSSLMODE=require
export PG_IP=$(kubectl get service acid-pg-main -o 'jsonpath={.spec.clusterIP}')
psql -h ${PG_IP} -U dbadmin postgres
```

Для удаления кластера:

```
kubectl delete postgresql acid-pg-main
```

## Хорошие статьи про этот оператор

https://habr.com/ru/company/flant/blog/520616/
https://habr.com/ru/company/flant/blog/527524/
