# Rancher's Local Path Provisioner

Использования local storage с sig static provisioner не полностью автоматизирует процесс.
Как минимум надо создать определённое количество fixed size блоков руками на каждой node'е для того, чтобы
этот provisioner работал.

Собственно по ссылке всё что надо [описано](https://github.com/rancher/local-path-provisioner).

Создаём `values.yml`:

```
nodePathMap:
  - node: DEFAULT_PATH_FOR_NON_LISTED_NODES
    paths:
      - /mnt/local-data
```

Создаём template и применяем его:

```
helm template -n local-path-storage default local-path-provisioner/deploy/chart/ -f values.yml > local-path-storage.yml
kubectl create namespace local-path-storage
kubectl apply -n local-path-storage
```
