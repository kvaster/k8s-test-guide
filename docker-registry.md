# Docker registry

Запустим docker registry внутри самого кубернетеса - для локальной разработки такой setup будет само то.

Реестр запустим на примере Persistent Volume Claim, local path в нашем случае (`docker-registry.yml`):

```
apiVersion: v1
kind: Namespace
metadata:
  name: docker-registry
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: docker-registry-pvc
  namespace: docker-registry
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 200Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docker-registry
  namespace: docker-registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: docker-registry
  template:
    metadata:
      labels:
        app: docker-registry
    spec:
      containers:
        - name: docker-registry
          image: registry:2.7.1
          env:
            - name: REGISTRY_HTTP_ADDR
              value: ":5000"
            - name: REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY
              value: "/var/lib/registry"
            - name: REGISTRY_HTTP_SECRET
              value: "somesecret"
          ports:
          - name: http
            containerPort: 5000
          volumeMounts:
          - name: image-store
            mountPath: "/var/lib/registry"
      volumes:
        - name: image-store
          persistentVolumeClaim:
            claimName: docker-registry-pvc
---
kind: Service
apiVersion: v1
metadata:
  name: docker-registry
  namespace: docker-registry
  labels:
    app: docker-registry
spec:
  selector:
    app: docker-registry
  ports:
  - name: http
    port: 5000
    targetPort: 5000
```

И ingress для него для доступа снаружи (`docker-registry-ingress.yml`):

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: docker-registry-ingress
  namespace: docker-registry
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: registry.kvaster.com
    http:
      paths:
        - path: /
          pathType: ImplementationSpecific
          backend:
            service:
             name: docker-registry
             port:
               number: 5000
  tls:
```

Возможные параметры конфигурации смотрим [тут](https://docs.docker.com/registry/configuration/).

TODO: описать как с ним работать
