# K8S - nginx ingress.

Для того, чтобы мы могли зайти на наши ресурсы из вне, нам надо настроить ingress сервис.
В данном guide'е сделаем это на основе nginx-ingress. Настроим два тестовых эхо сервиса и автоматическое
получение tls сертификатов.

## TODO

[ ] Настроить nginx ingress в виде DaemonSet вместо Deployment. Для мелкого кластера нам надо, чтобы nginx запускался на каждой машине.
[ ] Научиться настраивать Deployment (для большого кластера использовать DaemonSet не правильно) с node affinity - чтобы на каждой node запускался максимум один nginx ingress pod.

## Тестовые эхо сервисы.

Создадим два тестовых эхо сервиса:

```
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

## Установка самого nginx-ingress

Воспользуемся 'простым' способом. Для начала установим то, что обязательно надо для всех вариантов:

`kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/mandatory.yaml`

## Ingress сервис

Создаём ingress сервис. Хочу заметить, что тип в spec мы специально указываем `ClusterIP`, чтобы сервис не был в виде
`NodePort`, как указано в примере для baremetal. Плюс мы добавляем секцию `externalIPs` с помощью которой как раз и
выставляем наружу наш ingress. В `externalIPs` мы должны перечислить все внешние ip, которые мы используем.

```
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
    - name: https
      port: 443
      targetPort: 443
      protocol: TCP
  externalIPs:
  - 159.69.129.18
  - 159.69.129.19
  - 159.69.129.20
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
---
```

А теперь настроим ingress сервис и укажем наши 2 эхо сервиса:

```
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: letsencrypt
spec:
  rules:
  - host: kube.mydomain.com
    http:
      paths:
        - path: /apple
          backend:
            serviceName: apple-service
            servicePort: 5678
        - path: /banana
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
