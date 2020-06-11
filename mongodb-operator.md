# MongoDB

Официальное описание: https://www.percona.com/doc/kubernetes-operator-for-psmongodb/kubernetes.html

Скачиваем репозитарий оператора:

```
git clone https://github.com/percona/percona-server-mongodb-operator
```

Переходим в папку с установочными файлами:

```
cd percona-server-mongodb-operator/deploy
```

Ищем в нём `persistentVolumeClaim`. Надо раскомментировать `storageClassName` и `accessModes`.
Также `storageClassName` надо установить в наши диски: `fast-disks`

Создаём описание crd:

```
kubectl apply -f crd.yaml
```

Создаём ns для оператора:

```
kubectl create namespace psmdb
```

Создаём права:

```
kubectl apply -f rbac.yaml --namespace=psmdb
```

Запускаем оператор:

```
kubectl apply -f operator.yaml --namespace=psmdb
```

Применяем default пароли:

```
kubectl apply -f secrets.yaml --namespace=psmdb
```

Пароли создаётся с помощью base64 - т.е. plain пароль кодируется в base64.
В стандартных настройках используется clusterAdmin / clusterAdmin123456

Также в `cr.yaml` надо поменять: `updateStrategy: RollingUpdate`. SmartUpdate - not supported.

И создаём наш тестовый кластер:

```
kubectl apply -f cr.yaml --namespace=psmdb
```

В самом начале мы нашему тестовому кластеру вписали правильный persistentVolumeClaim.

Проверяем: `kubectl get pods -n psmdb`

Ну и можем запустить клиента:

```
kubectl run -i --rm --tty percona-client --image=percona/percona-server-mongodb:4.0 --restart=Never -- bash -il
percona-client:/$ mongo "mongodb+srv://userAdmin:userAdmin123456@my-cluster-name-rs0.psmdb.svc.cluster.local/admin?replicaSet=rs0&ssl=false"
```
