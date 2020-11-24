# K8S - nginx ingress.

Для того, чтобы мы могли зайти на наши ресурсы из вне, нам надо настроить ingress сервис.
В данном guide'е сделаем это на основе ingress-nginx. Настроим два тестовых эхо сервиса и автоматическое
получение tls сертификатов.

Хочу сразу заметить, что запускать мы будем ingress-nginx от разработчиков kubernetes, а не nginx-ingress
от разработчиков nginx. Разницу можно почитуть [тут](https://github.com/nginxinc/kubernetes-ingress/blob/master/docs/nginx-ingress-controllers.md#differences-between-nginxinckubernetes-ingress-and-kubernetesingress-nginx-ingress-controllers).

## Тестовые эхо сервисы.

Создадим два тестовых эхо сервиса:

```
---
kind: Pod
apiVersion: v1
metadata:
  name: apple-app
  labels:
    app: apple
spec:
  containers:
    - name: apple-app
      image: hashicorp/http-echo
      args:
        - "-text=apple"
---
kind: Service
apiVersion: v1
metadata:
  name: apple-service
spec:
  selector:
    app: apple
  ports:
    - port: 5678 # Default port for image
```

и

```
---
kind: Pod
apiVersion: v1
metadata:
  name: banana-app
  labels:
    app: banana
spec:
  containers:
    - name: banana-app
      image: hashicorp/http-echo
      args:
        - "-text=banana"
---
kind: Service
apiVersion: v1
metadata:
  name: banana-service
spec:
  selector:
    app: banana
  ports:
    - port: 5678 # Default port for image
```

Ну и конечно применим это всё в кластер с помощью `kubectl apply -f ...`.

## Установка самого ingress-nginx

Данный ingress можно устанавливать двумя способами:

* С помощью готового yml файла, но в этом случае его надо будет руками редактировать.
* С помощью helm'а.

### Установка с помощью готового yml файла.

Разработчики подготавливают разные варианты установки. Воспользуемся вариантом для baremetal'а:

```
wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/baremetal/deploy.yaml`
```

Найдём секцию сервиса в этом файле. Поиск делаем по тегу `controller-service.yaml`.
В секции spec поменяем `NodePort` на `ClusterIP`. Плюс мы добавляем секцию `externalIPs` с помощью которой как раз и
выставляем наружу наш ingress. В `externalIPs` мы должны перечислить все внешние ip, которые мы используем.
По итогу эта секция будет выглядеть примерно так:

```
# Source: ingress-nginx/templates/controller-service.yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    helm.sh/chart: ingress-nginx-2.10.0
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/version: 0.33.0
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/component: controller
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 80
      protocol: TCP
      targetPort: http
    - name: https
      port: 443
      protocol: TCP
      targetPort: https
  externalIPs:
  - 10.118.11.20
  - 10.118.11.21
  - 10.118.11.22
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/component: controller
---
```

Также поменяем настройки deploy'я для нас. Вместо deployment сделаем запуск на всех вершинах - в виду Daemonset'а.
Делаем поиск секции по тегу `controller-deployment.yaml`. В нём меняем `kind` с `Deployment` на `Daemonset`.
Начало секции будет выглядеть примерно так:

```
# Source: ingress-nginx/templates/controller-deployment.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    helm.sh/chart: ingress-nginx-3.10.1
```

### Установка с помощью helm chart'а

Готовые yml файлы для установки разработчики сами генерируют из своих helm chart'ов, но есть один нюанс - в просто
сгенерированных таких файлах нету создания отдельного namespace'а, ну и весь chart не учитывает того, в какой namespace
класть все объекты. Соответственно надо передавать эти параметры при установке в cli.

Для начала добавим репозитарий ingress-nginx к себе:

```
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
```

Создаём файл, который переопределит стандартные свойства - `values.yml`.
Вписываем в него всё то, что меняли в предыдущей секции и ещё чуть-чуть:

```
namespace: ingress-nginx
controller:
  kind: DaemonSet
  service:
    type: ClusterIP
    externalIPs:
    - 10.118.11.20
    - 10.118.11.21
    - 10.118.11.22
  publishService:
    enabled: false
```

Генерируем yml файл и запускаем его:

```
helm template -n ingress-nginx ingress-nginx ingress-nginx/ingress-nginx --version 3.11.0 -f values.yml > ingress.yml
kubectl create namespace ingress-nginx
kubectl apply -n ingress-nginx -f ingress.yml
```

## Настройка сервисов для работы с TLS

А теперь настроим ingress сервис и укажем наши 2 эхо сервиса:

```
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: letsencrypt
spec:
  rules:
  - host: kube.mydomain.com
    http:
      paths:
        - path: /apple
          pathType: ImplementationSpecific
          backend:
            serviceName: apple-service
            servicePort: 5678
        - path: /banana
          pathType: ImplementationSpecific
          backend:
            serviceName: banana-service
            servicePort: 5678
  tls:
  - hosts:
    - 'mydomain.com'
    - '*.mydomain.com'
    secretName: mydomain-wildcard-cert
```

В аннотациях указываем нашего certification issuer'а, которого ранее создали.
Также добавляем секцию tls и вписываем настройки для wildcard сертификата.

Проверяем создание сертификата:

`kubectl get certificates -A`

`kubectl describe certificate mydomain-wildcard-cert`

`kubectl describe certificaterequest mydomain-wildcard-cert-961098960`

И теперь проверяем наши url'ы: `https://kube.mydomain.com/apple` и `https://kube.mydomain.com/banana`.

## Переиспользование сертификата

В предыдущем описании мы использовали так называемый `ingress-shim` для автоматического создания сертификата.
`ingress-shim` активизируется с помощью аннотации: `cert-manager.io/cluster-issuer: letsencrypt`.

Проблема с таким подходом в том, что с таким подходом нам надо для каждого `Ingress` задавать свой отдельный
`tls.secretName` (иначе мы можем в определённый момент потерять сертификат вообще для какого-нибудь из ingress сервисов).
А это в свою очередь будет означать, что мы будем создавать/пересоздавать сертификат с одинаковыми параметрами много раз.
И это всё приведёт к тому, что мы придём к limit rate'у от letsencrypt.

Для уменьшения количества сертификатов и запросов к letsencrypt нам надо управлять сертификатами самим. Для этого надо
удалить аннотацию и создать `Certificate` руками. Т.е. мы выбираем сколько различных наборов сертификатов
(разные домены, разные наборы поддоменов и т.д.) нам надо и для каждого набора создать свой сертификат.

Создаём сертификат согласно [документации](https://cert-manager.io/next-docs/usage/certificate/):

```
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: kvaster-cert
  annotations:
    #cert-manager.io/issue-temporary-certificate: true
spec:
  # Secret names are always required.
  secretName: kvaster-cert
  renewBefore: 360h # 15d
  dnsNames:
  - kvaster.com
  - "*.kvaster.com"
  privateKey:
    rotationPolicy: Always
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
```

Прошу обратить внимание и почитать в документации на: `rotationPolicy: Always`, а так же на закомментированную аннотацию.
Также для автоматического удаления секрета при удалении объекта `Certficiate`, надо включать опцию, описанную в документации.

## Копирование секретов

В kubernetes pod имеет доступ только к тем секретам, которые находятся в одном с ним namespace'е.
Это значит, что если нам надо использовать один и тот же сертификат для сервисов в разных namespace'ах, то secret с
полученным сертификатом надо копировать в разные namespace'ы.

Для этого можно использовать разные методы: [kubed](https://cert-manager.io/next-docs/faq/kubed/),
[ClusterSecret](https://github.com/zakkg3/ClusterSecret).

Также в таком случае можно использовать вместо `ClusterIssuer` простой `Issuer`, создавать сертификаты только в одном
namespace'е с `Issuer` и копировать их в нужные namespace'ы.

## Default certificate

Один из стандартных случаев - использование одного wildcard сертификата вместо того, чтобы создавать много отдельных.
В этом случае мы можем использовать настройку `--default-ssl-certificate` в ingress nginx.

Для начала создадим в namespace'е `ingress-nginx` наш wildcard сертификат с именем `default-cert` (см. выше как).

Для разворачивания из готового yml находим в нём секцию по тегу `controller-deployment.yaml` и добавляем в `args`
ещё один параметр запуска - `--default-ssl-certificate=ingress-nginx/default-cert`. `args` по итогу будут выглядеть
примерно так:

```
args:
  - /nginx-ingress-controller
  - --election-id=ingress-controller-leader
  - --ingress-class=nginx
  - --configmap=$(POD_NAMESPACE)/ingress-nginx-controller
  - --validating-webhook=:8443
  - --validating-webhook-certificate=/usr/local/certificates/cert
  - --validating-webhook-key=/usr/local/certificates/key
  - --default-ssl-certificate=ingress-nginx/default-cert
```

Для варианта с helm добавляем в `values.yml` точно такой же параметр. Итоговый values.yml будет выглядеть так:

```
namespace: ingress-nginx
controller:
  kind: DaemonSet
  extraArgs:
    default-ssl-certificate: ingress-nginx/default-cert
  service:
    type: ClusterIP
    externalIPs:
    - 10.118.11.20
    - 10.118.11.21
    - 10.118.11.22
  publishService:
    enabled: false
```

В ingress сервисе в tls секции надо убрать `secretName`, а в `hosts` можно повторить то же самое, что в `host` в `http` секции:

```
  tls:
  - hosts:
    - 'kube.mydomain.com'
```

## Небольшие замечание по acme (letsencrypt) сертификатам

Крайне рекомендую почитать информацию по acme [тут](https://cert-manager.io/docs/configuration/acme/).

Уже сейчас letsencrypt может получать сертификат по двум разным chain'ам - с помощью старого root'а и
с помощью своего нового. С 1-го января 2021-го года по стандарту будет использован новый root.
Об этом написано [тут](https://cert-manager.io/docs/configuration/acme/#use-an-alternative-certificate-chain).

Cert-manager при установке зарегистрирует новый аккаунт. Если вы хотите использовать свой старый аккаунт, то для
этого надо отключить создание нового и в ручном режиме создать секрет с вашим ключём:
[читать тут](https://cert-manager.io/docs/configuration/acme/#reusing-an-acme-account).
