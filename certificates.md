# K8S - сертификаты.

В нашем случае мы будем использовать letsencrypt для получения сертификатов. Чтобы меньше напрягать сам сервис (у него есть rate limit), будем использовать wildcard сертификаты. Воспользуемся kubernetes сервисом [cert-manager](https://cert-manager.io).

## Установка

### Готовый манифест

Установим его в наш кластер согласно официальному guide'у:

`kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.4.0/cert-manager.yaml`

можем проверить, что всё хорошо:

`kubectl get pods -n cert-manager`

### Helm

```
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager --create-namespace --namespace cert-manager --version v1.4.0 --set installCRDs=true
```

Обновление:

```
helm upgrade cert-manager jetstack/cert-manager --namespace cert-manager --version v1.4.0 --set installCRDs=true
```

## Настройка

Настроим с помощью yaml файла через kubectl. Пример конфигурации для letsencrypt staging:

```
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: viktor@mydomain.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Secret resource used to store the account's private key.
      name: mydomain-acme-key
    solvers:
    - dns01:
        rfc2136:
          nameserver: 116.116.116.116:53
          tsigKeyName: letsencrypt.
          tsigAlgorithm: HMACSHA512
          tsigSecretSecretRef:
            name: mydomain-tsig-secret
            key: mydomain-tsig-secret-key
      selector:
        dnsZones:
        - 'mydomain.com'
```

Для production заменим имя в metadata и заменим server на `https://acme-v02.api.letsencrypt.org/directory`.

В качестве solver'а для dns01 типа аутентификации (читай что это такое в letsencrypt) воспользуемся rfc2136 стандартом.
Собственно все мои предыдущие скрипты этот делали примерно таким же способом с помощью cert-bot'а.
Нам понадобится IP нашего dns сервера. Использовать dns имя почему-то запрещается (надо будет разобраться).
При настройке bind (не входит в этот guide) мы генерировали глючик котрому выдавали права на обновление acme-challenge.
Делали мы это с помощью команды:

`tsig-keygen -a hmac-sha512 letsencrypt.`

В наших настройках `tsigKeyName` это `letsencrypt.`. А вот secret этого ключа мы должны вставить в секреты kubernetes сами:

`kubectl -n cert-manager create secret generic mydomain-tsig-secret --from-literal=mydomain-tsig-secret-key=<somesecret>`

Где `mydomain-tsig-secret` - это всего лишь имя секрета внутри kubernetes, а `mydomain-tsig-secret-key` - это имя ключа внутри секрета.

Данная настройка не создаст самих сертификатов - она лишь создаст способ с помощью которого в будущем создавать сертификаты.
И этот способ описан на примере в [ingress-nginx](ingress-nginx.md).
