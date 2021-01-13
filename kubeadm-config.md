# kubeadm config

Конфигурация kubeadm состоит из трёх частей:
* InitConfiguration
* ClusterConfiguration
* KubeletConfiguration

Для bootstrap'а нужны все части конфигурации и мы прописываем их 'руками'.
Но иногда нам надо иметь возможность пересоздать файлы манифестов или какие-то другие из папки `/etc/kubernetes`.
Мы можем вносить в них изменения руками, но в этом случае надо будет вносить изменения и туда и в configmap'ы конфигурации kubeadm.

Kubeadm хранит свои конфигурации в двух configmap'ах в ns kube-system: kubeadm-config и kubelet-config-VER (kuberlet-config-1.20, например).
Для того, чтобы воссоздать kubeadm.yml нам надо запустить следующий скрипт:

```
kubectl get configmap -n kube-system kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' > kubeadm.yml
echo --- >> kubeadm.yml
kubectl get configmap -n kube-system kubelet-config-1.20 -o jsonpath='{.data.kubelet}' >> kubeadm.yml
```

Сразу хочу заметить, что InitConfiguration секция восстановлена не будет, но она нам и не нужна.

Ну и в качестве примера впоследствии перегенерирование манифеста запуска kube-scheduler (`/etc/kubernetes/manifests/kube-scheduler.yaml`):

```
kubeadm init phase control-plane scheduler --config kubeadm.yml
```
