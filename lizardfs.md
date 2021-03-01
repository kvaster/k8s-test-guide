# Lizardfs

Иногда нам нужен конкретно persistent volume, который не зависит от ноды, на которой запущен pod (сетевой).
В качестве такого volume'а мы можем использовать в том числе и lizardfs.

На текущий момент нет lizardfs драйвера в CSI реализации, но есть драйвер в flexvolume реализации.
После небольших патчей он может поддерживать fuse3 вариант коннекта к lizardfs.

Сам драйвер находится [тут](https://github.com/kvaster/lizardfs-flexvolume).

Так же для этого драйвера в моём репозитарии есть ebuild.
Драйвер надо поставить пакетом на каждую ноду вашего кластера - это сейчас единственный вариант для flexvolume.
Также в системе должен стоять собственно сам fuse3 драйвер от lizardfs.

После этого можно посмотреть пример deployment'а...

## Пример mount'а с помощью pvc

Для начала надо создать сам persistent volume:

```
kind: PersistentVolume
apiVersion: v1
metadata:
  name: lizardpv
  labels:
    type: lizardpv
spec:
  storageClassName: lizardfs
  capacity:
    storage: 1Ti
  accessModes:
    - ReadWriteMany
  flexVolume:
    driver: "fq/lizardfs"
    options:
      host: "mfsmaster"
      port: "9421"
      mfssubfolder: "/somesubpath"
      mfspassword: "somepass"
  persistentVolumeReclaimPolicy: Retain
```

Хочу заметить, что размер storage'а тут указывается по сути только в качестве reference'а,
так как он ни на что не влияет в реальности.

А дальше создадим persistent volume claim, которым сможем впоследствии воспользоваться:

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lizardpvc
spec:
  storageClassName: lizardfs
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  selector:
    matchLabels:
      type: lizardpv
```

И внутри pod'ов мы можем воспользваться таким claim'ом как любым другим:

```
  volumes:
    - name: test
      persistentVolumeClaim:
        claimName: lizardpvc
```
