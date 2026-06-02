# CloudFormation — Labs Alta Disponibilidad (M2C2)

Templates de infraestructura para el modulo de Alta Disponibilidad. Crean recursos **dinamicos** que se eliminan al finalizar cada lab. La VPC, subnets, route tables e IAM role/profile SSM son pre-requisitos persistentes creados manualmente por el alumno.

> Las guias del curso usan AWS Console. Este README documenta que crea cada template y que parametros pide para evitar confusiones durante el lab.

---

## `ha-lab1-nodes.yaml` — 2 nodos API para demo ALB

**Usado en:** Lab HA-01

**Crea:**
- 2 EC2 Amazon Linux 2023 con Flask API (una por AZ, en subnets publicas del lab)
- SG de nodos API: acepta `:5000` solo desde el SG del ALB (parametro `AlbSgId`)
- App expone `/health`, `/api/v1/health`, `/api/v1/crash`, `/health/deep`

**Por que subnets publicas:** el lab no usa NAT Gateway. Las instancias necesitan salida a internet durante bootstrap (`dnf`, `pip3`). El SG evita acceso directo desde Internet al puerto 5000.

**Parametros requeridos:**

| Parametro | Descripcion |
|---|---|
| `VpcId` | ID de la VPC del lab |
| `SubnetAId` | Subnet publica AZ-A |
| `SubnetBId` | Subnet publica AZ-B |
| `AlbSgId` | SG del ALB creado manualmente antes del deploy |
| `SsmInstanceProfile` | Instance Profile SSM creado como pre-requisito |

**Stack name sugerido:** `cloudcuyo-ha-lab1-nodes`

**Outputs:** `ApiNode1Id`, `ApiNode1Ip`, `ApiNode2Id`, `ApiNode2Ip`, `ApiNodeSgId`

**Nota importante:** `ApiNodeSgId` pertenece a este stack. Cuando se elimina `cloudcuyo-ha-lab1-nodes` al comenzar HA-02, ese SG tambien se elimina. HA-02 crea un SG manual nuevo (`cloudcuyo-api-node-sg`) para los nodos del ASG.

---

## `ha-lab2-traffic-gen.yaml` — Traffic Generator

**Usado en:** Lab HA-02 y Lab HA-03

**Crea:**
- EC2 en subnet publica con IP publica (SSM via internet, sin NAT Gateway)
- SG propio (solo egress)
- Regla adicional en el SG de los nodos API: permite `:5000` desde el generador (para crash directo en Lab HA-03)
- Script `cloudcuyo-load.sh`: carga continua con `ab` contra el ALB
- Script `cloudcuyo-crash-node.sh`: envia `/crash` a una IP privada especifica
- Servicio systemd `cloudcuyo-load` que arranca automaticamente durante el UserData

**Parametros requeridos:**

| Parametro | Descripcion |
|---|---|
| `VpcId` | ID de la VPC del lab |
| `PublicSubnetId` | Subnet publica para el generador |
| `ApiSgId` | SG manual de los nodos del ASG (`cloudcuyo-api-node-sg`, creado en HA-02 Fase 1.2) |
| `SsmInstanceProfile` | Instance Profile SSM |
| `AlbTargetUrl` | URL completa del ALB, ej: `http://cloudcuyo-api-alb-xxx.us-east-1.elb.amazonaws.com` |

**Parametros opcionales:** `RequestsPerSecond` (default: 30), `Workers` (default: 5), `LatestAmiId` (default: latest Amazon Linux 2023 via SSM public parameter)

**Stack name sugerido:** `cloudcuyo-ha-traffic-gen`

**Outputs:** `TrafficGeneratorInstanceId`, `TrafficGeneratorPublicIp`, `SsmConnectCommand`, `LoadLogCommand`, `CrashNodeCommand`

**Comportamiento importante:** la carga empieza sola. El servicio `cloudcuyo-load` queda `enabled` y `running` al terminar el bootstrap. Para detenerlo en una sesion SSM:

```bash
sudo systemctl stop cloudcuyo-load
```

---

## Orden de limpieza

Al finalizar HA-03, eliminar en este orden:

1. Stack `cloudcuyo-ha-traffic-gen`
2. Auto Scaling Group `cloudcuyo-api-asg`
3. Launch Template `cloudcuyo-api-lt`
4. ALB `cloudcuyo-api-alb`
5. Target Group `cloudcuyo-api-tg`
6. Security Groups manuales (`cloudcuyo-api-node-sg`, `cloudcuyo-alb-sg`)

> No eliminar con los stacks: VPC, subnets, route tables, IAM role/profile SSM. Son pre-requisitos persistentes.
