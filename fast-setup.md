# Как нам быстро развернуться

## Bootstrap кластера

* Устанавливаем виртуалки:

Для libvirtd:

```shell script
ansible-playbook -e repo_domain=myhost.com playbooks/vm.yml
```

Или для virtual box:

```shell script
ansible-playbook -e repo_domain=myhost.com vm_type=vbox playbooks/vm.yml
```

* Для начала удостоверимся, что в manifests ничего нету (надо будет сделать, чтобы это было автоматически). Это надо
будет делать на всех машинах, включаемых в кластер:

```shell script
ls -a /etc/kubernetes/manifests
# There may be .keep_sys-cluster_kubernetes-0 in there. Remove if present:
rm -Rf /etc/kubernetes/manifests
```

Последний kubeadm слишком рьяно проверяет наличие файлов в этом каталоге на bootsrap'е

* На первой машине запускаем bootstrap k8s:

```shell script
cd k8s
sh kube-setup.sh
```

Команда выдаст две версии команд для join'а: для добавления вершины control plane и для добавления вершины worker'а.
На k8s-2 и k8s-3 запускаем команду для control plane'а, а для k8s-4 - для worker'а. Запоминаем обе команды.

* На вершинах, где в кластере предполагается наличие control plane, запускаем первую команду с добавлением следующего
параметра (ip адрес должен присутствовать на машине, где запускается команда):

```shell script
cd k8s
<kubectl join variant for control plane> --apiserver-advertise-address 10.118.12.XX
sh kube-postjoin.sh
```

*  На одной из машин, например, на первой (k8s-1), даем команду на установку CNI cilim.

Перед запуском надо установить helm cilium репозитарий:
```shell script
helm repo add cilium https://helm.cilium.io/
```

```shell script
sh cilium-helm.sh && kubectl apply -f cillium.yml
```

Для того, чтобы продолжить, надо подождать пока появится сеть. Проверить можно, например, так:

```shell script
kubectl get pods
```

* На вершинах, которые будут обычными worker без control plane запускаем:

```shell script
cd k8s
<kubectl join variant for worker>
sh kube-postjoin.sh
```

ВАЖНО: worker можно bootstrap'ить только после того, как мы запустим сеть (см. предыдущий шаг)

## Запуск тестовых сервисов

TODO
