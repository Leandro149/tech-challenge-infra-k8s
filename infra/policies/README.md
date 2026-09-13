# Política IAM do AWS Load Balancer Controller

`load-balancer-controller.json` é a política oficial da release **v3.5.0**, usada pelo chart Helm **3.5.0** em `platform/controllers.tf`.

Origem: https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/docs/install/iam_policy.json

Licença do projeto original: Apache-2.0. A política é vendorizada para não depender de downloads durante o plan/apply. Ao atualizar o controller, revisar e atualizar a política e os CRDs conforme as instruções oficiais: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/

A role é restrita ao service account `kube-system/aws-load-balancer-controller` pelo issuer OIDC, subject e audience. A política oficial contém ações de descoberta com Resource `*` e condições por tags para recursos gerenciados pelo controller.
