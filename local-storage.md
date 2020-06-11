# Local storage

## Auto provisioning

Сливаем репозитарий с автоматическим provisioning:

```
git clone https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner
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

```
cd /mnt
mkdir fast-disks
mount -o noatime,nodiratime /dev/sda2 fast-disks
cd fast-disks
btrfs subvolume create k8s
cd k8s
btrfs subvolume create k8s-root
btrfs subvolume create k8s-1
btrfs subvolume create k8s-2
btrfs subvolume create k8s-3
btrfs subvolume create k8s-4
btrfs subvolume create k8s-5

mkdir k8s-root/k8s-1
mkdir k8s-root/k8s-2
mkdir k8s-root/k8s-3
mkdir k8s-root/k8s-4
mkdir k8s-root/k8s-5
```

Убираем mount - он был временным:

```
cd /mnt
umount fast-disks
```

Добавляем в fstab:

```
/dev/sda2  /mnt/fast-disks  btrfs noatime,nodiratime,space_cache=v2,discard=async,compress=zstd,subvol=k8s/k8s-root,rshared  0 0
/dev/sda2  /mnt/fast-disks/k8s-1  btrfs noatime,nodiratime,space_cache=v2,discard=async,compress=zstd,subvol=k8s/k8s-1,rshared  0 0
/dev/sda2  /mnt/fast-disks/k8s-2  btrfs noatime,nodiratime,space_cache=v2,discard=async,compress=zstd,subvol=k8s/k8s-2,rshared  0 0
/dev/sda2  /mnt/fast-disks/k8s-3  btrfs noatime,nodiratime,space_cache=v2,discard=async,compress=zstd,subvol=k8s/k8s-3,rshared  0 0
/dev/sda2  /mnt/fast-disks/k8s-4  btrfs noatime,nodiratime,space_cache=v2,discard=async,compress=zstd,subvol=k8s/k8s-4,rshared  0 0
/dev/sda2  /mnt/fast-disks/k8s-5  btrfs noatime,nodiratime,space_cache=v2,discard=async,compress=zstd,subvol=k8s/k8s-5,rshared  0 0
```

mount'им (при перезапуске mount будет автоматом):

```
mount /mnt/fast-disks
mount /mnt/fast-disks/k8s-1
mount /mnt/fast-disks/k8s-2
mount /mnt/fast-disks/k8s-3
mount /mnt/fast-disks/k8s-4
mount /mnt/fast-disks/k8s-5
```

Запускаем наш чарт:

```
kubectl apply -f deployment/kubernetes/provisioner_generated.yaml
```

Ну и смотрим:

```
kubectl get pv -A
```

