# CloudFormation — Labs Alta Disponibilidad (M2C2)

Templates de infraestructura para el módulo de Alta Disponibilidad. Crean recursos **dinámicos** que se eliminan al finalizar cada lab. La VPC, subnets, route tables e IAM role SSM son pre-requisitos persistentes creados manualmente por el alumno.

---

## `ha-lab1-nodes.yaml` — 2 nodos API para demo ALB

**Usado en:** Lab HA-01

**Crea:**
- 2 EC2 Amazon Linux 2023 con Flask API (una por AZ, subnet privada)
- SG interno: acepta `:5000` solo desde el SG del ALB (parámetro)
- App expone `/health`, `/api/v1/health`, `/api/v1/crash`, `/health/deep`

**Parámetros requeridos:**

| Parámetro | Descripción |
|---|---|
| `VpcId` | ID de la VPC del lab |
| `PrivateSubnetAId` | Subnet privada AZ-A |
| `PrivateSubnetBId` | Subnet privada AZ-B |
| `AlbSgId` | SG del ALB creado manualmente antes del deploy |
| `SsmInstanceProfile` | Instance Profile SSM creado como pre-requisito |

**Stack name sugerido:** `cloudcuyo-ha-lab1-nodes`

**Outputs:** `ApiNode1Id`, `ApiNode1Ip`, `ApiNode2Id`, `ApiNode2Ip`, `ApiNodeSgId`

```bash
aws cloudformation create-stack \
  --stack-name cloudcuyo-ha-lab1-nodes \
  --template-body file://cloudformation/ha-lab1-nodes.yaml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=$VPC_ID \
    ParameterKey=PrivateSubnetAId,ParameterValue=$PRIVATE_SUBNET_A_ID \
    ParameterKey=PrivateSubnetBId,ParameterValue=$PRIVATE_SUBNET_B_ID \
    ParameterKey=AlbSgId,ParameterValue=$ALB_SG_ID \
    ParameterKey=SsmInstanceProfile,ParameterValue=$SSM_INSTANCE_PROFILE
```

---

## `ha-lab2-traffic-gen.yaml` — Traffic Generator

**Usado en:** Lab HA-02 y Lab HA-03

**Crea:**
- EC2 en subnet pública con IP pública (SSM via internet, sin costo extra)
- SG propio (solo egress)
- Regla adicional en el SG de los nodos API: permite `:5000` desde el generador (para crash directo en Lab HA-03)
- Script `cloudcuyo-load.sh`: carga continua con `ab` contra el ALB
- Script `cloudcuyo-crash-node.sh`: envía `/crash` a una IP privada específica
- Servicio systemd `cloudcuyo-load` que arranca automáticamente

**Parámetros requeridos:**

| Parámetro | Descripción |
|---|---|
| `VpcId` | ID de la VPC del lab |
| `PublicSubnetId` | Subnet pública para el generador |
| `ApiSgId` | SG de los nodos API (output `ApiNodeSgId` del stack `cloudcuyo-ha-lab1-nodes`, o SG creado en HA-01) |
| `SsmInstanceProfile` | Instance Profile SSM |
| `AlbTargetUrl` | URL completa del ALB, ej: `http://cloudcuyo-alb-xxx.us-east-1.elb.amazonaws.com` |

**Parámetros opcionales:** `RequestsPerSecond` (default: 30), `Workers` (default: 5)

**Stack name sugerido:** `cloudcuyo-ha-traffic-gen`

**Outputs:** `TrafficGeneratorInstanceId`, `SsmConnectCommand`, `LoadLogCommand`, `CrashNodeCommand`

```bash
aws cloudformation create-stack \
  --stack-name cloudcuyo-ha-traffic-gen \
  --template-body file://cloudformation/ha-lab2-traffic-gen.yaml \
  --parameters \
    ParameterKey=VpcId,ParameterValue=$VPC_ID \
    ParameterKey=PublicSubnetId,ParameterValue=$PUBLIC_SUBNET_A_ID \
    ParameterKey=ApiSgId,ParameterValue=$API_NODE_SG_ID \
    ParameterKey=SsmInstanceProfile,ParameterValue=$SSM_INSTANCE_PROFILE \
    ParameterKey=AlbTargetUrl,ParameterValue=http://$ALB_DNS \
    ParameterKey=RequestsPerSecond,ParameterValue=30 \
    ParameterKey=Workers,ParameterValue=5
```

---

## Limpieza

```bash
# Lab HA-01 (eliminar antes de Lab HA-02)
aws cloudformation delete-stack --stack-name cloudcuyo-ha-lab1-nodes

# Labs HA-02 y HA-03 (eliminar al finalizar el módulo)
aws cloudformation delete-stack --stack-name cloudcuyo-ha-traffic-gen
```

> **No eliminar con stacks:** VPC, subnets, route tables, IAM role SSM. Son pre-requisitos persistentes.
