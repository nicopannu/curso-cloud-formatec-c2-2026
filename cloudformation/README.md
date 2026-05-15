# CloudFormation - Bootstrap para CloudCuyo

## Template disponible

**`nat-instance.yaml`** - Bootstrap completo: NAT Instance + IAM Roles

**Recursos creados:**
- ✅ **NAT Instance** (Amazon Linux 2023) para Internet egress
- ✅ **IAM Role vmimport** para importar VMs como AMIs
- ✅ **IAM Role + Instance Profile** para SSM Session Manager
- ✅ Security Groups configurados
- ✅ Elastic IP
- ✅ Ruta automática en Route Table privada

**Costo:** $0/mes con Free Tier

---

## Desplegar

### Bash

```bash
aws cloudformation create-stack --stack-name cloudcuyo-nat --template-body file://cloudformation/nat-instance.yaml --parameters ParameterKey=VpcId,ParameterValue=$VPC_ID ParameterKey=PublicSubnetId,ParameterValue=$PUBLIC_SUBNET_ID ParameterKey=PrivateRouteTableId,ParameterValue=$PRIVATE_RT_ID ParameterKey=KeyPairName,ParameterValue=cloudcuyo-key --capabilities CAPABILITY_NAMED_IAM
```

### PowerShell

```powershell
New-CFNStack -StackName "cloudcuyo-nat" -TemplateBody (Get-Content "cloudformation\nat-instance.yaml" -Raw) -Parameter @(@{ ParameterKey="VpcId"; ParameterValue=$VpcId }, @{ ParameterKey="PublicSubnetId"; ParameterValue=$PublicSubnetId }, @{ ParameterKey="PrivateRouteTableId"; ParameterValue=$PrivateRtId }, @{ ParameterKey="KeyPairName"; ParameterValue="cloudcuyo-key" }) -Capability CAPABILITY_NAMED_IAM
```

---

## Obtener outputs del stack

### Bash

```bash
# Instance Profile para SSM (usar en todas las EC2)
SSM_PROFILE_NAME=$(aws cloudformation describe-stacks --stack-name cloudcuyo-nat --query 'Stacks[0].Outputs[?OutputKey==`SSMInstanceProfileName`].OutputValue' --output text)

# Verificar que el rol vmimport se creó
aws iam get-role --role-name vmimport
```

### PowerShell

```powershell
# Instance Profile para SSM
$SsmProfileName = (Get-CFNStack -StackName "cloudcuyo-nat").Outputs | Where-Object { $_.OutputKey -eq "SSMInstanceProfileName" } | Select-Object -ExpandProperty OutputValue

# Verificar rol vmimport
Get-IAMRole -RoleName vmimport
```

---

## Conectar a instancias via SSM

### Bash

```bash
aws ssm start-session --target i-xxxxxxxxx
```

### PowerShell

```powershell
Start-SSMSession -Target i-xxxxxxxxx
```

---

## Eliminar

### Bash

```bash
aws cloudformation delete-stack --stack-name cloudcuyo-nat
```

### PowerShell

```powershell
Remove-CFNStack -StackName "cloudcuyo-nat" -Force
```
