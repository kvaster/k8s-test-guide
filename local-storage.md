# Local storage

## Auto provisioning

Сливаем репозитарий с автоматическим provisioning:

```
git clone https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner
cd sig-storage-local-static-provisioner
```

Создаём storage class (будет называться fast-disks):

```
kubectl apply -f deployment/kubernetes/example/default_example_storageclass.yaml
```

Создаём по helm template'у нужные нам файлы:

```
helm template --name-template=test ./helm/provisioner > deployment/kubernetes/provisioner_generated.yaml
```

В helm/provisioner/values.yaml можно увидеть mount point для всех наших дисков.

Перед тем как применять сгенерированный yaml, надо создать mount point и создать сами диски.
K8s не умеет забирать папки. Он умеет забирать только целые mount point'ы.
Мы используем btrfs, поэтому мы можем просто создать пачку subvolumes и использовать их.
Но надо их сделать отдельным mount point'ом каждый:

```shell script
cd /mnt
mkdir pvs
mount -o noatime,nodiratime /dev/sda2 pvs
cd pvs
btrfs subvolume create k8s
cd ..
umount pvs

echo "/dev/sda2  /mnt/pvs  btrfs noatime,nodiratime,space_cache=v2,discard=async,compress=zstd,subvol=k8s,rshared  0 0
/dev/sda2  /mnt/fast-disks  btrfs noatime,nodiratime,space_cache=v2,discard=async,compress=zstd,subvol=k8s/k8s-root,rshared  0 0" >>/etc/fstab
mount /mnt/pvs
cd pvs
btrfs subvolume create k8s-root
mount /mnt/fast-disks
```

Запускаем наш чарт:

```shell script
kubectl apply -f deployment/kubernetes/provisioner_generated.yaml
```

В следующем разделе показано, как добавлять новые PV.

## Операции над Persistent Volumes

### Добавление PV

Создаем скрипт для создания новый PV

```shell script
cat <<EOF >add-pv.sh
mkdir /mnt/pvs/k8s-root/\$1
btrfs subvolume create /mnt/pvs \$1
echo "/dev/sda2  /mnt/fast-disks/\$1  btrfs noatime,nodiratime,space_cache=v2,discard=async,compress=zstd,subvol=k8s/\$1,rshared  0 0" >>/etc/fstab
mount /mnt/fast-disks/\$1
EOF
chmod +x add-pv.sh
```

И исполняем нужное количество раз

```shell script
for i in $(seq 5); do ./add-pv k8s-$i; done
```

### Список PV и соответствующие им локальные пути

Показать список активных PV

```shell script
kubectl get pv -A
```

Список: путь к PV mount, имя PV, имя вершины

```shell script
kubectl get pv -o jsonpath="{range .items[*]}[{.spec.local.path}, {.metadata.name}, {.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}]{'\n'}"
```

### Удаление PersistentVolume, mount и subvolume

Предполагается, удаление PV будет редкой операцией в нашем setup'е. 

```shell script
cat <<EOF >remove-pv.sh
# Removes given LocalStorage PersistentVolume from the current node
# $1 - mount name, matches btrfs subvolume name. If name is abc then mount is /mnt/fast-disks/abc and btrfs subvolume is k8s/abc
# Script assumes that node name is equal to $HOSTNAME
PV=$(kubectl get pv -o json |\
  jq -r ".items|map(select(.spec.local.path==\"/mnt/fast-disks/$1\" and "\
".spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]==\"$HOSTNAME\"))|map(.metadata.name)[0]")

set -x
umount /mnt/fast-disks/$1
kubectl delete pv "$PV"
sed -i "/subvol=k8s\/$1/d" /etc/fstab
rmdir /mnt/fast-disks/$1
btrfs subvolume delete /mnt/pvs/$1
EOF
chmod +x remove-pv.sh
```

Предположим надо удалить PV, соответствующий subvolume `k8s-5`.

```shell script
./remove-pv.sh k8s-5
```

Здесь есть некоторый шанс, что после umount кто-то успеет запросить PersistentVolumeClaim (PVC) на удаляемый PV.
Чтобы этого не произошло можно останавливать static provisioner и позже вновь его запускать:

```shell script
kubectl delete ds test-provisioner
# Then delete necessary volumes and run again from ~/k8s
kubectl apply -f sig-storage-local-static-provisioner/deployment/kubernetes/provisioner_generated.yaml
```

Note: Если имя вершины не совпадает с `$HOSTNAME`, то 
[здесь](https://github.com/stedolan/jq/issues/250) есть способ нахождения имени текущей вершины.

TODO: Найти более "красивый" способ удаления PV на конкретной машине без остановки provisioner на всех машинах.
