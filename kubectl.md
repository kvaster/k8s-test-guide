# Kubectl и OpenID Connect (OIDC)

## Настройка сервера

На сервере надо разрешить доступ к kube-apiserver. Замените адрес API_SERVER, если он другой. Выполните следующуее
на всех входящий серверах, которые будут включены в DNS запись нашего сервера (например kapi.example.com). В DNS запись
можно включить, например, несколько серверов из группы ingress. В нашем случае они доступны через внешние IP VLAN.

```shell script
API_SERVER=10.118.12.100
cat <<EOF > /etc/local.d/iptables.start
#!/bin/sh
iptables -t mangle -I PREROUTING -i wan0 -p tcp --dport 6443 -j MARK --set-mark 1
iptables -t nat -I PREROUTING -m mark --mark 1 -j DNAT --to-destination $API_SERVER
iptables -t nat -I POSTROUTING -m mark --mark 1 -j MASQUERADE
EOF
chmod +x /etc/local.d/iptables.start
rc-update add local default
openrc
rc-service local start
```

Если FQDN, указывающий на kube-apiserver (например kapi.example.com) не включен в сертификат сервера, то сертификат надо
исправить перегенерировать. Сначала обновляем конфигурацию сервера. Потом на каждом сервере, включенным в DNS запись
(у нас kapi.example.com) удаляем старые сертификаты, пересоздаем сертификаты и перезапускаем kubelet. Последней командой
можно зайти на ip сервера извне и проверить, какие адреса включены в сертификат.

```shell script
kubeadm config view >kubeadmconf.yml
# Add kube-apiserver FQDN to apiServer.certSANs, e.g. kapi.example.com
vi kubeadmconf.yml
# Deprecated, but works. Proposes to use instead: kubeadm init phase upload-config
kubeadm config upload from-file --config kubeadmconf.yml

# Do the rest on each server
# Check cert before
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout|less
# Recreate
rm /etc/kubernetes/pki/apiserver.*
kubeadm init phase certs apiserver --config=kubeadmconf.yml
# Recheck
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout|less
# Restart kubelet
rc-service kubelet restart
# Check certificate externally.
openssl s_client -connect <ip or fqdn>:6443 | openssl x509 -noout -text
```

## OIDC

Для включения OIDC, необходимо в kube-apiserver добавить опции, проверящие что OIDC JWT Token выдан именно нашим
OIDC провайдером, которому мы доверяем. Например в случае с Google это:
- issuer-url: https://accounts.google.com
- client-id: xxx.apps.googleusercontent.com
- client-secret: xxx

Получение аккаунта описано, например, [тут](https://medium.com/@hbceylan/deep-dive-kubernetes-single-sign-on-sso-with-openid-connection-via-g-suite-a4f01bd4a48f)
и [тут](https://cloud.google.com/community/tutorials/kubernetes-auth-openid-rbac).

Далее необходимо добавить опции в apiserver. При добавлении новой вершины в кластер, kubeadm использует данные из
конфигурации кластера. При уже добавленной вершине, данные берутся из файла `/etc/kubernetes/manifests/kube-apiserver.yaml`.
На текущий момент (июль 2020) мне неизвестен автоматический способ применения конфигурации сразу и везде, поэтому
необходимо поменять конфигурацию и обновить manifest на всех узлах Control Plane. Ниже описаны из

```yaml
# Add this to kubeadmconf.yml (see below)
apiServer:
  extraArgs:
    # Add only following 4 lines. The rest is already there.
    oidc-client-id: xxx.apps.googleusercontent.com
    oidc-issuer-url: https://accounts.google.com
    oidc-username-claim: email
    oidc-groups-claim: groups
# Add this to /etc/kubernetes/manifests/kube-apiserver.yaml on all Control Plane nodes
spec:
  containers:
  - command:
    - kube-apiserver
    # Add only following 3 lines. The rest is already there.
    - --oidc-issuer-url=https://accounts.google.com
    - --oidc-username-claim=email
    - --oidc-client-id=301523111073-hapgi8mcivo3ci1uv0tlqnspq4rtme84.apps.googleusercontent.com
```

Команды, которые необходимо выполнить:

```shell script
kubeadm config view >kubeadmconf.yml
# Add the info described above
vi kubeadmconf.yml
# Deprecated, but works. Proposes to use instead: kubeadm init phase upload-config
kubeadm config upload from-file --config kubeadmconf.yml

# Do the next lines on all Control Plane nodes.
# Edit the file as described above
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Restart kubelet
rc-service kubelet restart
```

*TODO:* перегенерировать конфиг можно в автоматическом режиме с помощью kubeadm.

## Установка kubectl

Install `kubectl`: https://kubernetes.io/docs/tasks/tools/install-kubectl/

```shell script
# MacOS
brew install kubectl
```

Install `krew` packet manager for `kubectl`: https://krew.sigs.k8s.io/docs/user-guide/setup/install/

```shell script
(
  set -x; cd "$(mktemp -d)" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.{tar.gz,yaml}" &&
  tar zxvf krew.tar.gz &&
  KREW=./krew-"$(uname | tr '[:upper:]' '[:lower:]')_amd64" &&
  "$KREW" install --manifest=krew.yaml --archive=krew.tar.gz &&
  "$KREW" update
)
```

Add `$HOME/.krew/bin` to PATH, e.g. in `.bashrc`

Check if krew is working:

```shell script
kubectl krew
```

Install `kubectx`, `kubens`, and `fzf`:

https://github.com/ahmetb/kubectx#installation

https://github.com/junegunn/fzf
```shell script
# MacOS
brew install kubectx fzf
# For fzf keybinding (see https://github.com/junegunn/fzf#key-bindings-for-command-line)
/usr/local/opt/fzf/install
```

## Bash Completion for kubectl

```shell script
# MacOS
brew install bash-completion
```

Add lines e.g. to your .bashrc (or whatever was recommended after brew install above:

```shell script
[ -r /usr/local/etc/profile.d/bash_completion.sh ] && . /usr/local/etc/profile.d/bash_completion.sh
```

To apply in the current session:
```shell script
. ~/.bashrc
```

You can find more completion packages for bash-completion by running

```shell script
# MacOS
brew search completion
```

Kubectl bash-completion:
```shell script
echo 'source <(kubectl completion bash)' >>~/.bashrc
# For `k` alias:
echo 'alias k=kubectl' >>~/.bash_profile
echo 'complete -F __start_kubectl k' >>~/.bash_profile
```

## OIDC auth for kubectl

Install oidc-login on your client machine:

```shell script
kubectl krew install oidc-login
```

Create the ~/.kube/config using info below. Get missing data like CA from server's file `/etc/kubernetes/admin.conf`.
The `extra-scopes` field is needed if extra claims are needed for auth. Distribute the result config to engineers and
provide it to new engineers on onboarding.

```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: <CA data>
    server: https://kapi.viplay.dev:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    namespace: default
    user: oidc
  name: oidc@kubernetes
current-context: oidc@kubernetes
kind: Config
preferences: {}
users:
- name: oidc
  user:
    auth-provider:
      config:
        client-id: xxx.apps.googleusercontent.com
        client-secret: xxx
        extra-scopes: email
        idp-issuer-url: https://accounts.google.com
      name: oidc
```

Using `kubectl`:

```shell script
# To login
kubectl oidc-login
# Now kubectl should be working. Test by running e.g.:
kubectl cluster-info
```

Note, that Google OIDC doesn't provide refresh token. So user would need to re-login every hour. To avoid that it is
recommended to user some OIDC proxy, like `dex`, `AuthZ` or `Keycloak`.

Final token is provided to kube-apiserver. It confirmes the signature, extracts the claims, checks issuer-id. Final
username depends on a chosen claim (`--oidc-username-claim` argument):
- If claim is `email`, then username is the value of that claim.
- If claim is anything else then username is `<iss claim value>#<claim value defined by oidc-username-claim>`, e.g.
with Google OIDC and sub claim equal to `12345` the value is `https://accounts.google.com#12345`

Links:
- https://www.youtube.com/watch?v=yaJnT6DNHHc
- https://www.youtube.com/watch?v=gJ81eaGlN_I
- https://cloud.google.com/community/tutorials/kubernetes-auth-openid-rbac
- https://kubernetes.io/docs/reference/access-authn-authz/authentication/
