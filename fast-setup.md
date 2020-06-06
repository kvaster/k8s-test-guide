# Как нам быстро развернуться

* Устанавливаем виртуалки:

Для libvirtd:

```
ansible-playbook -e repo_name=myhost.com playbooks/vm.yml
```

Или для virtual box:

```
ansible-playbook -e repo_name=myhost.com vm_type=vbox playbooks/vm.yml
```

* Для начала удостоверимся, что в manifests ничего нету (надо будет сделать, чтобы это было автоматически):

```
rm /etc/kubernetes/manifests/.keep_sys-cluster_kubernetes-0
```

Последний kubeadm слишком рьяно проверяет наличие файлов в этом каталоге на bootsrap'е

* На первой машине запускаем bootstrap k8s:

```
cd k8s
sh kube-setup.sh
```

Команда выдаст две версии команд для join'а - для control plane и для worker'а.
На k8s-2 и k8s-3 запускаем команду для control plane'а, а для k8s-4 - для worker'а.

ВАЖНО: при запуске команды для control plane мы должны в неё добавить ещё один параметр:

```
--apiserver-advertise-address 10.118.12.XX
```

После того, как команда отработает, надо запустить: `sh kube-postjoin.sh`

Каждый сервер бутстрапится отдельно.

ВАЖНО: worker можно bootstrap'ить только после того, как мы запустим сеть (см. следующий шаг)

* Запуск сети

Запускаем на k8s-1:

```
sh cilium-helm.sh
```

Данная команда установит cilium helm репозитарий и создаст cilium.yaml файл для запуска сети.

Нам останется только запустить наш k8s файлик:

```
kubectl apply -f cilium.yaml
```

Для того, чтобы продолжить, надо подождать пока появится сеть.
