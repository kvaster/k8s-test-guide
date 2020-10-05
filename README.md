# K8S

Данный проект - проба раскатывания bare metal kubernetes кластера.
Начнём с тестового setup'а.

## Быстрый setup

Для быстрого запуска воспользуемся готовым [быстрым гайдом](fast-setup.md)

## Нерешённые вопросы

Начнём сразу с нерешённых или до конца не решённых вопросов.

**High priority**
* [ ] Разобраться с общими параметрами health check для кластера. Это ``node-status-update-frequency`` для kubelet, ``node-monitor-period``, ``node-monitor-grace-period``, ``pod-eviction-timeout`` для controller-manager. Инфа [тут](https://habr.com/ru/company/flant/blog/326062/).
* [ ] Задача внутренних адресов для control plane решается тем, чтобы резолвить hostname в правильный ip адрес. Самый простой способ это сделать - добавить имя и ip в ``/etc/hosts``, но я не уверен на сколько это хорошее решение. Если задавать ``--hostname-override``, то часть сервисов всё равно использует другой ip и как следствие весь кластер не поднимается. Но ``hostname -i`` для определения главного адреса сервера может использоваться и в других сервисах.

**Medium priority**
* [ ] Load balancing для control plane
* [ ] HA и Load Balancing для control plane перенесённый внутрь самого kubernetes
* [ ] etcd backup ([см. тут](#etcd))
* [ ] Ротация внутренних сертификатов и их backup
* [x] Ротация внешних сертификатов (https://cert-manager.io). Решение находится [тут](certificates.md)
* [ ] Выбрать ingress контроллер (nginx, skipper e.t.c.).
* [ ] Надо как-нибдь разобраться с kubernetes federation и cilium cluster mesh. Это надо для запуска в режиме гибридных кластеров.
* [ ] Мониторинг сервисов. Понятно что прометей, но надо его прикручивать.
* [ ] Сбор логов сервисов.

**Low priority**
* [ ] Машины для control plane всегда фиксированные ? Надо описать весь процесс управления ими в случае проблем.
* [ ] Шифрованная связь между нодами. Надо ли и как лучше реализовывать (cilium, wireguard e.t.c.). На старте мы используем сеть без шифрования на базе ipvlan и шифрование реализовываем посредством tls между сервисами.
* [ ] Сделать правильный auto scale для coredns - чтобы они разворачивались автоматом равномерно по кластеру

## После настройки тестового окружения

- [Внешние сертификаты](certificates.md)
- [NGINX ingress](nginx-ingress.md)

## Тестовое окружение

Для тестирования кластера нам понадобится три виртуальные машины. В качестве примера возьмём virt-manager (libvirtd).
В реальности можно использовать любой способ виртуализации (VirtualBox и т.д.).

### Виртуальные машины

Тестовый сетап будет имитировать (в каком-то виде) настройку сети в hetzner.
В частности там для каждого сервера выдаётся отдельный ip, а для L2 сегмент можно запросить отдельный vlan и повесить
на него отдельный pool внешних адресов. Как следствие сервера смогут 'ходить в интернет' по разным путям.

Нам понадобится две сети:

``10.118.10.0/24`` типа NAT (настройка для libvirt: [net-qemu.xml](conf/libvirt/net-qemu.xml))

``10.118.11.0/24`` также типа NAT (настройка для libvirt: [net-qemu-shadow.xml](conf/libvirt/net-qemu-shadow.xml)

Настраиваем три машины (пример для libvirt: [machine.xml](conf/libvirt/machine.xml)).

Каждая машина содержит один sata диск. Для libvirt они появятся в виде ``/dev/vda``. Если будет использоваться другой
способ виртуализации, то названия дисков надо будет заменить в ``ansible/hostvars/*.yml``.

В каждой машине добавляется две сетевые карты. Первая должна смотреть в первую сеть, а вторая, соответственно, во вторую.
В базовом сетапе ОС мы используем permanent iface names и делаем это на mac адресах, так что мак адреса сетевых карт
должны соответствовать конфигу в ansible: ``ansible/hostvars/*.yml``.

После настройки запускаемся с gentoo minimal install (вообще подойдёт почти любой live образ).

Смотрим на каком интерфейсе у нас появилась dhcp ip и вешаем на неё адрес конкретной машины:

``ip addr add 10.118.10.20/24 dev eth0``

Меняем пароль: ``passwd``

И запускаем sshd: ``/etc/init.d/sshd start``

Автоматически раскатываем OS:

```bash
ansible-playbook -e host=k8s-1 -e force_clean=true -e ansible_user=root -e ansible_ssh_pass=MYPASS playbooks/gentoo-install.yml
```

### Настройки машин для kubernetes

Сеть изначально будет автоматически настроена ansible скриптом из предыдущей секции.
На одном интерфейсе будет ip из ``10.118.10.0/24`` согласно настройкам сети для этого интерфейса,
а вот для второго интерфейса мы специально выбрали ip из под сети ``10.118.12.0/24``.
IP для доступа во вне со второго интерфейса будут выделяться с помощью ``keepalived``.

Также хочу отметить настройку dns серверов в ``resolv.conf`` - согласн RFC libc должно поддерживать 3 dns сервера.
В большинстве дистрибутивов именно так и есть. Очень редко встречаются варианты, где это число равно 6.
А kubernetes'у надо добавлять к этим записям минимум ещё одну для внутреннего определения сервисов.
Как следствие у нас не должно быть больше 2-х записев в ``resolv.cof``.

Для работы с kubernetes нам понадобятся следующие пакеты:

* ``app-emulation/containerd``
* ``app-emulation/cri-tools``
* ``net-firewall/conntrack-tools``
* ``net-firewall/ebtables``
* ``net-misc/socat``
* ``sys-apps/ethtool``
* ``sys-apps/dbus`` - нужен только для того, чтобы сгенерировался файл ``/etc/machine-id``
* ``sys-cluster/kubernetes``
* ``app-admin/helm`` - для генерации конфигурации cilium

Для kubernetes пакета нам надо выключить все не нужные нам компоненты - нужны только kubeadm, kubelet и kubectl.
Добавляем в файл `/etc/portage/package.use/common.use`:

`sys-cluster/kubernetes -kube-apiserver -kube-controller-manager -kube-proxy -kube-scheduler`

Установить же это всё можно командой:

```
emerge -av app-emulation/containerd \
    app-emulation/cri-tools \
    net-firewall/conntrack-tools \
    net-firewall/ebtables \
    net-misc/socat \
    sys-apps/ethtool \
    sys-apps/dbus \
    sys-cluster/kubernetes \
    app-admin/helm
```

В качестве CNI (network plugin) мы будем использовать cilium в режиме, в котором он заменяет kube-proxy.
В таком режиме нам не нужны никакие модули bridge'ей, но kubeadm всё равно будет пытаться делать pre-flight check
и ругаться на отсутствие модуля, поэтом просто добавим его в автозагрузку в ``/etc/conf.d/modules``:

``modules="br_netfilter"``

Вместе с kubernetes будут поставлены также инструменты для контейнера: `cri-tools`, но в mainline portage не устанавливается
стандартный конфиг для них, поэтому надо вписать в `/etc/crictl.yaml`:

```
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
```

Для работы kubernets нам также понадобится изменить настройки параметров ядра в ``/etc/sysctl.conf``:

Сервер должен работать в режиме 'роутера': ``net.ipv4.ip_forward = 1``.

Для работы c virtual ip (keepalived) сервисы должны уметь делать bind на виртуальный адрес в то время,
когда он нам не принадлежит:

```
net.ipv4.ip_nonlocal_bind = 1
net.ipv6.ip_nonlocal_bind = 1
```

Я раньше увеличивал local port range, для увеличения количества соединений, но в реальности этого делать нельзя.
Kubernetes аллоцирует под себя нижний диапазон портов (cilium повторяет за ним), чтобы при локальной перекидке
пакетов не надо было делать nat. Т.е. параметр ``net.ipv4.ip_local_port_range`` должен оставаться в default value.

Из минорных вещей можно улучшить репортинг по памяти и включить опцию в `/etc/rc.conf`:

```
rc_cgroup_memory_use_hierarchy="yes"
```

Мы будем использовать cilium, а он в свою очередь использует bpf внутри себя для обработки пакетов.
Подсистема bpf может быть автоматически примонтирована и через сам контейнер cilium'а, но в этом случае при
падении контейнера bpf подсистема будет на время пропадать - т.е. будет пропадать сеть. Поэтому рекомендуется
монтировать bpf подсистему с помощью fstab в host системе. В ``/etc/fstab`` прописываем:

``none  /sys/fs/bpf  bpf  rshared  0 0``

На текущий момент (версия 1.19.0) kubernetes больше не требует дополнительных патчей, чтобы нормально запускаться на
openrc (gentoo), а также делать upgrade без kube-proxy, но раньше мы использовали свою патченую версию и в ней мы
кроме всего прочего вписывали правильные стартовые параметры для kubelet. Поэтому после установки из gentoo mainline
важно эти параметры проставить самим в `/etc/conf.d/kubelet`:

```
###
# Kubernetes Kubelet (worker) config

KUBEADM_ENV="/var/lib/kubelet/kubeadm-flags.env"
[[ -f "${KUBEADM_ENV}" ]] && . "${KUBEADM_ENV}"

KUBELET_KUBECONFIG_ARGS="--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
KUBELET_CONFIG_ARGS="--config=/var/lib/kubelet/config.yaml"

KUBELET_EXTRA_ARGS=""

command_args="${KUBELET_KUBECONFIG_ARGS} ${KUBELET_CONFIG_ARGS} ${KUBELET_KUBEADM_ARGS} ${KUBELET_EXTRA_ARGS}"
```

*ВНИМАНИЕ!*
Для kubernetes 1.9 и выше на btrfs надо выключить опцию ограничения local storage, иначе всё крашится:

```
KUBELET_EXTRA_ARGS="--feature-gates='LocalStorageCapacityIsolation=false'"
```

* https://github.com/kubernetes/kubernetes/issues/65204 (see last comments)
* https://github.com/kubernetes/kubernetes/issues/94335
* https://github.com/ubuntu/microk8s/issues/1570
* https://github.com/ubuntu/microk8s/issues/1587

### HA режим для control panel

Control plane отличается от остальных сервисов тем, что каждый control plane работает отдельно.
И на текущий момент в kubeadm не предусмотрено стандартного механизма для HA этих компонентов.
В cloud вариантах во всех туториалах предлагают использовать механизм load balancer'а от облачных провайдеров.
В данном тесте мы сделаем HA для control plane с помощью механизма вне kubernetes.

Для этого ставим нужный нам пакет: ``emerge -av sys-cluster/keepalived``

(полный конфиг для keepalived для первой ноды можно посмотреть тут: [keepalived.conf](conf/k8s/keepalived.conf)

Настраиваем keepalived для первой ноды в ``/etc/keepalived/keepalived.conf``:

```
vrrp_instance control_plane {
    state BACKUP
    interface wan1
    virtual_router_id 5
    priority 100
    advert_int 1
    authentication {
        auth_type AH
        auth_pass somepass
    }
    virtual_ipaddress {
        10.118.12.100/24
    }
}
```

Для остальных вершин делаем такой же конфиг.
Важно понимать, что при такой конфигурации ip будет оставать у того сервера, который ее забрал.
Т.е. во время bootstrap лучше запускать keepalived на дополнительных серверах только после полного запуска.

Стартуем и добавляем keepalived в автостарт:

```
/etc/init.d/keepalived start
rc-update add keepalived
```

**ВНИМАНИЕ!**

Хочу заметить, что такой setup не контролируется kubernetes, а так же в этом варианте keepalived не делает health check
самих control plane. Это значит, что если keepalived будет работать, а контейнеры по какой-то причине упадут вместе с kubectl,
то virtual ip останется на этом сервере и apiserver станет недоступен.

### HA режим для трафика из вне

Мы выбрали решение при котором внешний трафик идёт на pool внешних ip адресов с примерно равномерным распределением.
(dns round robin). Мы повесили внутреннюю сеть ``10.118.12.0/24`` на вторую сетевую карту (на которой собственно kubernetes
и запускаем), но в реальности шлюз для этой сетевой - ``10.118.11.1/24``. Возьмём N ip адресов из подсети данного шлюза
и распределим их в автоматическом режиме между нашими серверами.

Для каждого ip адреса на каждом сервере добавляем следующие секции в keepalived:

```
vrrp_instance wan_0 {
    state BACKUP
    interface wan1
    virtual_router_id 10
    priority 100
    advert_int 1
    authentication {
        auth_type AH
        auth_pass somepass
    }
    virtual_ipaddress {
        10.118.11.20
    }
}
```

``virtual_router_id`` на каждом сервере должен соответствовать virtual ip и должен быть разным для разных virtual ip.

``priority`` надо распределить так, чтобы при всех работающих серверах ip распределились равномерно, т.е. для сервера k8s-1 -
10.118.11.20=100, 10.118.11.21=99, 10.118.11.22=98, для k8s-2 10.118.11.20=98, 10.118.11.21=100, 10.118.11.22=99 и т.д.

Теперь надо надо настроить routes для того, чтобы трафик, который приходит на эти ip адреса шёл через правильный интерфейс. Для этого в ``/etc/iproute2/rt_tables`` добавляем: ``1  vswitch`` (только для того, чтобы обращаться по имени
к дополнительной таблице маршрутизации). Далее на каждом сервере прописываем правила роутинга и маршрутизации на эту таблицу в
``/etc/conf.d/net``:

```
routes_wan1="
10.118.11.0/24 dev wan1
10.118.11.0/24 dev wan1 scope link table vswitch
10.118.12.0/24 dev wan1 scope link table vswitch
default via 10.118.11.1 table vswitch
"
```

Не забываем заменить ``10.118.12.20`` на правильный ip на каждом сервере.

В итоге если мы будем слать изнутри на ``10.118.11.0/24``, то будет использовать ip из внутренней нашей сети в качестве src
(``10.118.12.x``), если же пакет придёт из вне, то для отправки обратного пакета будет использовать ip на который изначально
пакет пришёл, а по ip rule в этом случае будет использоваться другая таблица маршрутизации (vswitch).

### Bootstrap первого control plane

Для старта первого control plane будем использовать ``kubeadm`` с конфигурацией в yaml формате.
Пример конфигурации можно посмотреть тут: [kubeadm.yaml](conf/k8s/kubeadm.yaml)

В этой конфигурации надо обратить внимание на некоторые настройки:
* localAPIEndpoint.advertiseAddress - это ip адрес на котором будет слушать конкретно этот api server, т.е. адрес локального сервера
* controlPlaneEndpoint - а тут надо использовать virtual ip, который мы сделали с помощью keepalived - в реальности все сервисы будут ходить именно на этот ip адрес
* podSubnet - выделяем адресное пространство для подов, в нашем случае каждая нода получит пространство ``10.244.XX.*``
* serviceSubnet - это отдельно ip пространство для сервисов (сервис представляет собо виртуальный ip, который в свою очередь мапится на какое-то количество реальных pod'ов)

Настравием ``/etc/hosts`` для того, чтобы kubeadm и остальные сервисы автоматом определили главный ip адрес нашей машины: ``10.118.12.20 k8s-1``. Аналогичные настройки надо сделать на всех машинах.

Запускаем и добавляем в автозапуск containerd сервис:

```
/etc/init.d/containerd start
rc-update add containerd
```

Полный скрипт для запуска bootstrap находится тут: [kube-setup.sh](kube-setup.sh)

Запускаем kubeadm:

``kubeadm init --config kubeadm.yaml --skip-phases=addon/kube-proxy --upload-certs``

* ``--skip-phases=addon/kube-proxy`` - мы будем использовать cilium в режиме замены kube-proxy
* ``--upload-certs`` - с этой опцией kubeadm зальёт рутовые сертификаты в зашифрованном виде в своё хранилище. Это позволит не копировать их руками для запуска новых control plane

Для удобства копируем настройки для управления кластером через kubectl:

```
mkdir -p ~/.kube/config
cp /etc/kubernetes/admin.conf ~/.kube/config
```

Мы сетапим кластер, в котором три ноды и на каждой ноде мы хотели бы не только control plane, но и возможность что-то другое запускать, поэтому убираем taint для этой вершины:

``kubectl taint nodes k8s-1 node-role.kubernetes.io/master:NoSchedule-``

Напоследок добавляем kubectl в автозапуск:

``rc-update add kubectl``

**ВНИМАНИЕ!**

После того, как kubeadm отработает, он выдаст две команды: для join'а нового control plane и для join'а нового worker'а.
Token сам по себе expire'ится через 24 часа и может быть перегенерирован с помощью команды ``kubeadm token create``.
Мы можем получить полную команду для join'а worker'а автоматически:

``kubeadm token create --print-join-command``

Для генерации новой команды добавления control plane'а вы должны использвать certificate-key:

``kubeadm token create --print-join-command --certificate-key <certficate_key>``

Сертификаты хранятся внутри kubernetes только в течение двух часов. Т.е. если прошло больше двух часов или же
вы потеряли ключ, то надо будет заново залить сертификты в шифрованное хранилище и получить новый ключ:

``kubeadm init phase upload-certs --upload-certs``

### Добавление network'а.

Напоминаем себе, что bpf систему мы уже добавили в auto mount в ``/etc/fstab``.

Без сети для pod'ов и сервисов в нашем кластере мы ничего не сможем запустить.
Мы будем использовать cilium в качестве CNI плагина. Также работу kube-proxy мы переложим на него.
Для генерации cilium.yaml файла, который можно будет применить на нашем кластере будем использовать ``helm``.
Скрипт, который делает нужный нам конфиг, находится вот тут: [cilium-helm.sh](cilium-helm.sh).
Для того, чтобы скрипт заработал, сначала надо добавить helm репозитарий в систему: `helm repo add cilium https://helm.cilium.io/`.

Прошу обратить внимание, что в тех режимах, в которых мы его запускаем, cilium должен знать конкретный endpoint api server'а.
И этот endpoint - наш virtual ip.

После генерации конфига применим его:

``kubectl apply -f cilium.yaml``

### Добавление дополнительных control plane вершин

На каждой вершине по-очереди запускаем команду, об которой говорилось в предыдущих разделах:

```
kubeadm join <CONTROL_PLANE_ADDR>
    --token <TOKEN> \
    --discovery-token-ca-cert-hash <HASH> \
    --control-plane \
    --certificate-key <CERTIFICATE_KEY> \
    --apiserver-advertise-address <MY_IP>
```

где ``CONTROL_PLANE_ADDR`` равен ``10.118.12.100:6443``

**ВНИМАНИЕ!** в данной команде мы добавляем ещё один параметр - ``--apiserver-advertise-address``.
Так как мы в тесте заставляем слушать apiserver не на default интерфейсе, то тут важно указать адрес интерфейса,
который соответствует нашей внутренней сети. Для второго сервера в нашем случае это будет ``10.118.12.21``.

Если нам надо будет поднять чисто worker вершину, то надо убрать опции ``--control-plane`` и ``--certificate-key``.

Если мы добавляли новый control plane и собираемся использовать вершину не только для него, то не забываем убрать taint:

``kubectl taint nodes <NODE_NAME> node-role.kubernetes.io/master:NoSchedule-``

### Удаления вершин из кластера

Для удаления вершины из кластера нам надо сначала сделать ей drain - чтобы все pod'ы с этой вершины мигрировали на другие.

``kubectl drain <NODE_NAME>``

После этого удаляем вершину из кластера:

``kubectl delete node <NODE_NAME>``

Чистим за собой всё на самой вершине:

[kube-reset.sh](kube-reset.sh)

Убираем из автозапуска kubectl:

``rc-update del kubectl``

## Тестовые сервисы

### Устанавливаем dashboard

Тестовый dashboard последней версии можно установить следующим образом:

``kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended.yaml``

Далее для доступа надо будет создать аккаунт и добавить ему роль. Вот [здесь](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md) можно посмотреть более полное описане процесса.

## Об некоторых нюансах

### kubelet

Про параметры запуска можно почитать [тут](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/kubelet-integration).

Для production кластера надо по-хорошему подтюнить параметры GC для images и pod'ов, добавить опции
типа ``--maximum-dead-containers`` и т.д.
Про это описано [тут](https://v1-17.docs.kubernetes.io/docs/concepts/cluster-administration/kubelet-garbage-collection).

### etcd

При запуске control plane надо понимать, что только один из его компонентов является по сути statefull - это etcd.
Данный сервис на практике запускается только в трёх вариантах:
* Один на весь кластер в single control plane режиме. Такой вариант подходит только для тестов/разработки.
* Три на кластер. Это классический режим для не очень больших кластеров. Надо понимать, что режим в два сервера это даже хуже, чем режим в один сервер, так как кворум для двух серверов - это два.
* Пять на кластер. Такое режим рекомендуется для больших кластеров. При чём не рекомендуется вообще никогда запускать больше пяти инстансов etcd на один кластер.

Также из рекомендаций - это запускать etcd на машинах с быстрыми локальными хранилищами.

**TODO:** описать как делать backup etcd и восстановление в случае большого краха

Немного про оперирование etcd можно почитать [тут](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)

### Gentoo и оверлеи

Образ gentoo собирается с помощью скриптов https://github.com/kvaster/gentoo-build.

Дополнительные и изменённые пакеты (overlay) находятся в репозитарии: https://github.com/kvaster/kvaster-gentoo

В хост систему мы ставим только kubeadm, kubectl и kubelet.

Патч для отключения kube-proxy обновления нужен будет до тех пор, пока не будут пофикшены следующие issues:
[1756](https://github.com/kubernetes/kubeadm/issues/1756), [1318](https://github.com/kubernetes/kubeadm/issues/1318).

На текущий момент (kubernetes 1.19.0) патч для запуска на gentoo больше не нужен, также для сделан временный workaround для
пропускания фазы обновления kube-proxy.

### Обновление control plane'а

Документация по обновлению вот [тут](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/).
