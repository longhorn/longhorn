## Create Nginx Ingress Controller with basic authentication

1. Create a basic auth file `auth`:
> It's important the file generated is named auth (actually - that the secret has a key data.auth), otherwise the ingress-controller returns a 503

`$ USER=<USERNAME_HERE>; PASSWORD=<PASSWORD_HERE>; echo "${USER}:$(openssl passwd -stdin -apr1 <<< ${PASSWORD})" >> auth`

2. Create a secret

`$ kubectl -n longhorn-system create secret generic basic-auth --from-file=auth`

3. Create an Nginx ingress controller manifest `longhorn-ingress.yml` :

```
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: longhorn-ingress
  namespace: longhorn-system
  annotations:
    # type of authentication
    nginx.ingress.kubernetes.io/auth-type: basic
    # name of the secret that contains the user/password definitions
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    # message to display with an appropriate context why the authentication is required
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required '
spec:
  rules:
  - http:
      paths:
      - path: /
        backend:
          serviceName: longhorn-frontend
          servicePort: 80
```

4. Create the ingress controller:
`$ kubectl -n longhorn-system apply longhorn-ingress.yml`



#### For AWS EKS clusters:
User need to create an ELB to expose nginx ingress controller to the internet. (additional cost may apply)

1. Create pre-requisite resources: 
https://github.com/kubernetes/ingress-nginx/blob/master/docs/deploy/index.md#prerequisite-generic-deployment-command

2. Create ELB:
https://github.com/kubernetes/ingress-nginx/blob/master/docs/deploy/index.md#aws
