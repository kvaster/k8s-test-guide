# Local storage

## Auto provisioning

Сливаем репозитарий с автоматическим provisioning:

```shell script
git clone https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner
```

Создаём storage class (будет называться fast-disks):

```shell script
kubectl apply -f sig-storage-local-static-provisioner/deployment/kubernetes/example/default_example_storageclass.yaml
```

Создаём по helm template'у нужные нам файлы. Полный список опций, которые можно использовать в provisioner_values можно
посмотреть в sig-storage-local-static-provisioner/helm/provisioner/values.yaml.

```shell script
cat <<EOF >provisioner_values.yml
daemonset:
  nodeLabels:
    - kubernetes.io/hostname
EOF
helm template pv-provisioner --namespace kube-system --values provisioner_values.yml sig-storage-local-static-provisioner/helm/provisioner >provisioner_generated.yml
```

В helm/provisioner/values.yaml можно увидеть mount point для всех наших дисков.

Перед тем как применять сгенерированный yaml, надо создать mount point и создать сами диски.
K8s не умеет забирать папки. Он умеет забирать только целые mount point'ы.
Мы используем btrfs, поэтому мы можем просто создать пачку subvolumes и использовать их.
Но надо их сделать отдельным mount point'ом каждый:

```shell script
mkdir /mnt/pvs /mnt/fast-disks
VOLUME=UUID=$(grep -Po '(?<=^UUID=")[^"]*(?=.*subvol=root)' /etc/fstab)
mount -o noatime,nodiratime $VOLUME /mnt/pvs
btrfs subvolume create /mnt/pvs/k8s
umount /mnt/pvs

echo "$VOLUME  /mnt/pvs  btrfs noatime,nodiratime,space_cache=v2,discard=async,compress=zstd,subvol=k8s,rshared  0 0" >>/etc/fstab
mount /mnt/pvs
```

Запускаем наш чарт:

```shell script
kubectl apply -f provisioner_generated.yml
```

В следующем разделе показано, как добавлять новые PV.

## Операции над Persistent Volumes

### Добавление PV

Создаем скрипт для создания нового PV

```shell script
cat <<EOF >add-pv.sh
[ -z "\$1" ] && exit 1
mkdir /mnt/fast-disks/\$1
btrfs subvolume create /mnt/pvs/\$1
echo "UUID=$(grep -Po '(?<=^UUID=")[^"]*(?=.*subvol=root)' /etc/fstab)  /mnt/fast-disks/\$1  btrfs noatime,nodiratime,space_cache=v2,discard=async,compress=zstd,subvol=k8s/\$1,rshared  0 0" >>/etc/fstab
mount /mnt/fast-disks/\$1
EOF
chmod +x add-pv.sh
```

И исполняем нужное количество раз

```shell script
for i in $(seq 0 9); do ./add-pv.sh pv$i; done
```

### Список PV и соответствующие им локальные пути

Показать список активных PV

```shell script
kubectl get pv -A
```

Список: путь к PV mount, имя PV, имя вершины

```shell script
cat <<EOF >list-pv.sh
kubectl get pv -o jsonpath="{range .items[*]}[{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}, {.spec.local.path}, {.metadata.name}]{'\n'}{end}" | sort
EOF
chmod +x list-pv.sh
```

### Удаление PersistentVolume, mount и subvolume

Предполагается, удаление PV будет редкой операцией в нашем setup'е. 

```shell script
cat <<EOF >remove-pv.sh
# Removes given LocalStorage PersistentVolume from the current node
# \$1 - mount name, matches btrfs subvolume name. If name is abc then mount is /mnt/fast-disks/abc and btrfs subvolume is k8s/abc
# Script assumes that node name is equal to \$HOSTNAME
[ -z "\$1" ] && exit 1
PV=\$(kubectl get pv -l kubernetes.io/hostname=\$HOSTNAME -o jsonpath="{.items[?(.spec.local.path=='/mnt/fast-disks/\$1')].metadata.name}")

set -x
umount /mnt/fast-disks/\$1
kubectl delete pv "\$PV"
sed -i "/subvol=k8s\/\$1,/d" /etc/fstab
rmdir /mnt/fast-disks/\$1
btrfs subvolume delete /mnt/pvs/\$1
EOF
chmod +x remove-pv.sh
```

Note: Альтернативный способ нахождения PV на текущей вершине, не требующий метки равной имени вершины:
```shell script
PV=$(kubectl get pv -o json |\
  jq -r ".items|map(select(.spec.local.path==\"/mnt/fast-disks/$1\" and "\
".spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]==\"\$HOSTNAME\"))|map(.metadata.name)[0]")
```

Предположим надо удалить PV, соответствующий subvolume `k8s-5`.

```shell script
./remove-pv.sh k8s-5
```

Здесь есть некоторый шанс, что после umount кто-то успеет запросить PersistentVolumeClaim (PVC) на удаляемый PV.
Чтобы этого не произошло можно останавливать static provisioner и позже вновь его запускать:

```shell script
kubectl delete ds pv-provisioner
# Then delete necessary volumes and run again from ~/k8s
kubectl apply -f sig-storage-local-static-provisioner/deployment/kubernetes/provisioner_generated.yaml
```

Note: Если имя вершины не совпадает с `$HOSTNAME`, то 
[здесь](https://github.com/stedolan/jq/issues/250) есть способ нахождения имени текущей вершины.

TODO: Найти более "красивый" способ удаления PV на конкретной машине без остановки provisioner на всех машинах.

## Почему все так, а не иначе

- Хотелось не создавать отдельный volume для сервисов. Выбор пал на subvolume btrfs, который можно было маунтить как
файловую систему.
- Для того, чтобы provisioner видел mount points, надо чтобы /mnt/fast-disks было частью файловой системы, замаунченной
с опцией rshared. То есть надо либо маунтить `/` как rshared, либо создавать отдельный subvolume и маунтить его в
/mnt/fast-disks как rshared.
- Subvolume'ы можно было создавать в корне btrfs либо поместить в отдельный subvolume (k8s). По итогу решили поместить
в отдельный subvolume, чтобы все сабвольюмы в сабвольюме k8s были предназначены для одной и той же цели.
