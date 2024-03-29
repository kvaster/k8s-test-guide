# K8S - ingress nginx.

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

Данный ingress можно устанавливать ~~двумя способами~~:

* ~~С помощью готового yml файла, но в этом случае его надо будет руками редактировать.~~
* С помощью helm'а.

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
  config:
    enable-ocsp: 'true'
    ssl-session-cache-size: '50m'
    ssl-session-timeout: '1h'
    ssl-session-ticket-key: "Ayinjzn7b0Sr4DuXgItlEYExdGPVFqTKz5HWbxQWCneY71r272hbwS0uvgR20bgArOypH7biJEsPGrX2lL9OMN6wgApW4ZPjydQ7BLb/CXk="
    ssl-session-tickets: 'true'
    hsts: 'true'
    hsts-max-age: '15768000'
```

*ВНИМАНИЕ:* в `config` секции можно задавать разные параметры конфигурации самого nginx.
В частности `enable-ocsp` включить ocsp stapling. Параметры можно посмотреть [тут](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/).
Немного больше про параметры в секции ниже.

Устанавливаем (обновляем) с помощью helm:

```
helm upgrade --install --create-namespace -n ingress-nginx ingress-nginx ingress-nginx/ingress-nginx --version 4.0.13 -f values.yml
```

## Настройка сервисов для работы с TLS

А теперь настроим ingress сервис и укажем наши 2 эхо сервиса:

```
apiVersion: networking.k8s.io/v1
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
            service:
              name: apple-service
              port:
                number: 5678
        - path: /banana
          pathType: ImplementationSpecific
          backend:
            service:
              name: banana-service
              port:
                number: 5678
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
  name: mydomain-cert
  annotations:
    #cert-manager.io/issue-temporary-certificate: true
spec:
  # Secret names are always required.
  secretName: mydomain-cert
  renewBefore: 360h # 15d
  dnsNames:
  - mydomain.com
  - "*.mydomain.com"
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

В ingress сервисе в tls секции надо убрать `secretName`, а в `hosts` можно повторить то же самое, что в `host` в `http` секции (если надо SNI) или убрать вообще:

```
  tls:
```

Так же в `extraArgs` можно добавить ещё один параметр: `enable-ssl-chain-completion: true`.

## Небольшие замечание по acme (letsencrypt) сертификатам

Крайне рекомендую почитать информацию по acme [тут](https://cert-manager.io/docs/configuration/acme/).

Уже сейчас letsencrypt может получать сертификат по двум разным chain'ам - с помощью старого root'а и
с помощью своего нового. С 1-го января 2021-го года по стандарту будет использован новый root.
Об этом написано [тут](https://cert-manager.io/docs/configuration/acme/#use-an-alternative-certificate-chain).

Cert-manager при установке зарегистрирует новый аккаунт. Если вы хотите использовать свой старый аккаунт, то для
этого надо отключить создание нового и в ручном режиме создать секрет с вашим ключём:
[читать тут](https://cert-manager.io/docs/configuration/acme/#reusing-an-acme-account).

## Оптимизация nginx

Ранее мы выставили некоторые параметры для nginx. В частности мы выставили оптимизации для SSL:

```
enable-ocsp: 'true'
ssl-session-cache-size: '50m'
ssl-session-timeout: '1h'
ssl-session-ticket-key: "Ayinjzn7b0Sr4DuXgItlEYExdGPVFqTKz5HWbxQWCneY71r272hbwS0uvgR20bgArOypH7biJEsPGrX2lL9OMN6wgApW4ZPjydQ7BLb/CXk="
ssl-session-tickets: 'true'
hsts: 'true'
hsts-max-age: '15768000'
```

* `enable-ocsp` - включает ocsp stapling. Он работает немного не как родной в nginx, так как в ingress nginx
работа с сертификатами реализована на lua api (чтобы не перезагружать nginx при обновлении сертификата), но
параметр для ускорения работы tls - обязателен.

* `ssl-session-cache-size` - размер кеша ssl сессий для одного инстанса ingress'а
* `ssl-session-timeout` - время после которого мы будем точно делать полный tls handshake
* `ssl-session-tickets` - в случае, если у нас запущен не один pod ingress'а (а это будет так), то
ssl session cache будет актуален только на одном pod'е. Для того, чтобы можно было быстро начинать сессию
в случае если запрос попадает на другой pod, надо использовать ssl tickets. При этом ticket должен шифроваться
одним и тем же ключём.
* `ssl-session-ticket-key` - base64 закодированный ключ для ticket'ов. Его можно сгенерировать следующим
способом:

```
openssl rand 80 | openssl enc -A -base64
```

* `hsts` - включить Transport Security (будет с http перенаправлять всегда на https)
* `hsts-max-age` - максимальное время действия hsts
* `ssl-dh-param` - для хорошего полноценного tls security. Сделам по официальному [guide'у](https://kubernetes.github.io/ingress-nginx/examples/customization/ssl-dh-param/).

Для начала создадим наш общий ключик с помощью команды:

```
openssl dhparam 4096 2> /dev/null | base64
```

Создаём `dhparam.yml` и вписываем туда наш output одной стройкой:

```
apiVersion: v1
data:
  dhparam.pem: "LS0tLS1CRUdJTiBESCBQQVJBTUVURVJ..."
kind: Secret
metadata:
  name: dhparam
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
```

Применяем:

```
kubectl apply -f dhparam.yml
```

И вписываем в наш configmap (в values при изначальной установке):

```
ssl-dh-param: "ingress-nginx/dhparam"
```
