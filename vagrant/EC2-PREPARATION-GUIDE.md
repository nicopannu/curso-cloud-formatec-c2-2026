# Guía de Preparación de VMs para EC2

## 🎯 Objetivo

Preparar las VMs de CloudCuyo para que estén **100% listas para EC2** inmediatamente después de importarlas, permitiendo acceso via SSM Session Manager sin configuración adicional.

---

## 📋 Componentes Críticos Instalados

### 1. **cloud-init** (CRÍTICO para EC2)

**Por qué es necesario:**
- EC2 usa cloud-init para configurar instancias en el primer boot
- Sin cloud-init, la VM no obtendrá configuración de red, hostname, SSH keys, etc.

**Qué hace:**
- Obtiene metadata del servicio de metadatos de EC2 (169.254.169.254)
- Configura red automáticamente via DHCP
- Crea el usuario `ubuntu` con sudo
- Instala SSH keys desde EC2 key pair
- Configura hostname desde EC2 tags

**Configuración aplicada:**
```yaml
# /etc/cloud/cloud.cfg.d/90_ec2.cfg
datasource_list: [ Ec2, None ]
datasource:
  Ec2:
    metadata_urls: ['http://169.254.169.254']
```

---

### 2. **SSM Agent** (para Session Manager)

**Por qué es necesario:**
- Permite acceso a EC2 sin abrir puerto 22 (SSH)
- Más seguro que SSH tradicional
- No requiere IP pública ni bastion host
- Registra sesiones en CloudTrail

**Configuración aplicada:**
- Instalado via snap: `amazon-ssm-agent`
- Habilitado para iniciar en boot
- Detenido en local (se inicia automáticamente cuando detecta EC2)
- Limpieza de datos locales antes de export

---

### 3. **Usuario ssm-user** (AWS best practice)

**Por qué es necesario:**
- Usuario recomendado por AWS para SSM Session Manager
- Separación de privilegios vs usuario principal
- Configurado con sudo sin password para administración

**Configuración aplicada:**
```bash
useradd -m -s /bin/bash ssm-user
echo "ssm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ssm-user
```

---

### 4. **Usuario cloudadmin** (backup SSH)

**Por qué es necesario:**
- Acceso de respaldo si SSM falla
- Útil para troubleshooting
- Configurado con key + password

**Configuración aplicada:**
- Password: admin1234
- SSH key: /home/cloudadmin/.ssh/authorized_keys
- Sudo sin password

---

### 5. **Drivers EC2**

**Por qué son necesarios:**
- **ENA (Elastic Network Adapter)**: Red de alta velocidad en EC2
- **NVMe**: Acceso a volúmenes EBS (almacenamiento)

**Verificación aplicada:**
- Script verifica que módulos `ena` y `nvme` estén disponibles
- Ubuntu 22.04 incluye estos drivers por defecto

---

### 6. **Configuración de Red DHCP**

**Por qué es necesario:**
- EC2 asigna IPs via DHCP
- IPs estáticas no funcionan en VPC

**Configuración aplicada:**
```yaml
# /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
    ens5:
      dhcp4: true
```

---

### 7. **SSH Hardening**

**Configuración aplicada:**
- PubkeyAuthentication: yes (autenticación con keys)
- PasswordAuthentication: no (solo keys en producción)
- PermitRootLogin: no (root deshabilitado)
- UsePAM: yes (autenticación modular)

---

### 8. **Herramientas AWS CLI**

**Instaladas:**
- `awscli` - AWS Command Line Interface
- `python3-boto3` - SDK Python para AWS
- `ec2-instance-connect` - Para EC2 Instance Connect
- `jq` - Parser JSON (útil para scripts)

---

## 🔄 Proceso de Preparación

### Fase 1: Durante `vagrant up` (provision)

Cada script `setup-*.sh` ejecuta al final:

```bash
bash /vagrant/scripts/local/prepare-for-ec2.sh
```

**Lo que hace `prepare-for-ec2.sh`:**
1. ✅ Instala cloud-init
2. ✅ Configura cloud-init para datasource EC2
3. ✅ Crea usuario ssm-user
4. ✅ Verifica drivers EC2 (ENA, NVMe)
5. ✅ Configura netplan para DHCP
6. ✅ Hardening SSH
7. ✅ Configura SSM Agent
8. ✅ Instala herramientas AWS
9. ✅ Limpia cache y logs
10. ✅ Limpia datos de cloud-init (se regeneran en EC2)

---

### Fase 2: Antes de Export (finalización)

Script `regenerate-and-export.sh` ejecuta antes de apagar VMs:

```bash
vagrant ssh $vm -c "sudo bash /vagrant/scripts/local/finalize-for-export.sh"
```

**Lo que hace `finalize-for-export.sh`:**
1. ✅ **Remueve SSH host keys** - Se regeneran en EC2 (único por instancia)
2. ✅ **Limpia bash history** - No exportar comandos locales
3. ✅ **Limpia journald** - No exportar logs de desarrollo
4. ✅ **Limpia DHCP leases** - Se renuevan en EC2
5. ✅ **Limpia udev rules** - Se regeneran para nuevo hardware
6. ✅ **Limpia cloud-init data** - Forzar ejecución en próximo boot
7. ✅ **Trunca machine-id** - Se regenera en EC2 (único por instancia)
8. ✅ **Sync filesystem** - Asegurar que todo se escribió a disco

**Por qué remover estos datos:**
- SSH host keys deben ser únicos por instancia
- machine-id debe ser único por instancia
- cloud-init debe ejecutarse como "first boot" en EC2
- DHCP leases de VirtualBox no son válidos en AWS VPC

---

## 🚀 Flujo Completo: Local → AWS

### 1. Local (Vagrant)

```bash
vagrant up
# Ejecuta setup-*.sh → prepare-for-ec2.sh
# VM funcionando con todos los componentes
```

### 2. Export

```bash
bash scripts/local/regenerate-and-export.sh
# Ejecuta finalize-for-export.sh en cada VM
# Apaga VMs
# Exporta OVAs
```

### 3. Upload a S3

```bash
aws s3 sync /c/Users/Nico/exports-ova/ s3://curso-cloud-c2-2026-ovas/ --acl public-read
```

### 4. Import en AWS

```bash
aws ec2 import-image --disk-containers file://db01-import.json
```

### 5. Primer Boot en EC2

**Lo que sucede automáticamente:**

1. **cloud-init se ejecuta:**
   - Detecta datasource EC2
   - Obtiene metadata de 169.254.169.254
   - Configura red via DHCP
   - Genera nuevas SSH host keys
   - Crea usuario `ubuntu` con key del EC2 key pair
   - Configura hostname desde EC2

2. **SSM Agent se inicia:**
   - Detecta ambiente EC2
   - Se registra con Systems Manager
   - Queda disponible para Session Manager

3. **machine-id se regenera:**
   - systemd genera nuevo ID único
   - Evita conflictos con otras instancias

### 6. Acceso Inmediato

**Via SSM (RECOMENDADO):**
```bash
aws ssm start-session --target i-xxxxxxxxx
# Sin SSH, sin IP pública, sin Security Group
```

**Via SSH (si SG permite puerto 22):**
```bash
# Usuario creado por cloud-init
ssh -i lab-key.pem ubuntu@<ip-publica>

# Usuario de backup
ssh -i /c/clase-redes/lab-key.pem cloudadmin@<ip-publica>
```

---

## ✅ Verificación de Preparación

### En VM local (antes de export):

```bash
vagrant ssh db01

# Verificar cloud-init
cloud-init --version
ls -l /etc/cloud/cloud.cfg.d/90_ec2.cfg

# Verificar usuarios
id ssm-user
id cloudadmin

# Verificar SSM Agent
systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service

# Verificar drivers
modinfo ena
modinfo nvme

# Verificar netplan
cat /etc/netplan/50-cloud-init.yaml
```

### En EC2 (después de import):

```bash
# Conectar via SSM
aws ssm start-session --target i-xxxxxxxxx

# Verificar cloud-init ejecutó
sudo cloud-init status

# Verificar SSM registrado
sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service

# Verificar red DHCP
ip addr show

# Verificar hostname
hostname
cat /etc/hostname

# Verificar machine-id (debe ser diferente entre instancias)
cat /etc/machine-id
```

---

## 🔒 Seguridad

### Usuarios y Acceso

| Usuario | Propósito | Acceso SSH | Sudo | Origen |
|---------|-----------|------------|------|--------|
| `ubuntu` | Principal | Key (EC2) | NOPASSWD | cloud-init |
| `ssm-user` | SSM Session Manager | No | NOPASSWD | prepare-for-ec2.sh |
| `cloudadmin` | Backup | Key + Password | NOPASSWD | configure-ssh-access.sh |

### Credenciales de Lab (NO USAR EN PRODUCCIÓN)

- Password cloudadmin: `admin1234`
- SSH key: `/c/clase-redes/lab-key.pem`
- DB password: `cloudcuyo`

⚠️ **IMPORTANTE:** Cambiar en ambiente productivo

---

## 📊 Antes vs Después

### ❌ ANTES (Sin preparación)

**Import VM a EC2:**
1. ✅ VM arranca
2. ❌ Sin cloud-init → No obtiene config de EC2
3. ❌ Red no funciona (IP estática hardcoded)
4. ❌ SSM Agent no se registra
5. ❌ No se puede acceder sin SSH
6. ❌ Hostname incorrecto
7. ❌ Requiere User Data script para configurar
8. ❌ Mismo machine-id en todas las instancias

**Resultado:** VM arranca pero no es funcional en EC2

---

### ✅ DESPUÉS (Con preparación)

**Import VM a EC2:**
1. ✅ VM arranca
2. ✅ cloud-init detecta EC2 y configura todo
3. ✅ Red funciona via DHCP de VPC
4. ✅ SSM Agent se registra automáticamente
5. ✅ Acceso inmediato via SSM Session Manager
6. ✅ Hostname correcto desde EC2 tags
7. ✅ Usuario ubuntu creado con key
8. ✅ machine-id único por instancia
9. ✅ SSH host keys únicos por instancia

**Resultado:** VM 100% funcional en EC2, sin configuración adicional

---

## 🎓 Conceptos Clave

### cloud-init

Herramienta estándar de la industria para inicialización de instancias en la nube. Soportado por:
- AWS EC2
- Azure Virtual Machines
- Google Compute Engine
- OpenStack
- VMware vCloud

**Fases de cloud-init:**
1. **init**: Detectar datasource (EC2, Azure, etc.)
2. **config**: Aplicar configuración (red, usuarios, packages)
3. **final**: Ejecutar scripts finales

### EC2 Metadata Service

Servicio en 169.254.169.254 que provee:
- Instance ID
- AMI ID
- Instance type
- Public/private IP
- Security groups
- User data
- IAM role credentials
- Tags

### SSM Session Manager vs SSH

| Aspecto | SSH tradicional | SSM Session Manager |
|---------|----------------|---------------------|
| Puerto | 22 abierto | No requiere puertos |
| IP pública | Necesaria | No necesaria |
| Security Group | Debe permitir 22 | No requiere reglas |
| Bastion host | A veces necesario | No necesario |
| Auditoría | Logs locales | CloudTrail + S3 |
| Grabación | Manual | Automática opcional |
| MFA | Externo | Integrado con IAM |

---

## 📚 Referencias

- [AWS VM Import/Export](https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport-image-import.html)
- [cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [EC2 User Data and Metadata](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html)
- [Elastic Network Adapter (ENA)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/enhanced-networking-ena.html)

---

## 🐛 Troubleshooting

### VM no responde después de import

```bash
# Verificar que la AMI está disponible
aws ec2 describe-images --image-ids ami-xxxxx

# Ver logs de import
aws ec2 describe-import-image-tasks --import-task-ids import-ami-xxxxx

# Conectar via EC2 Instance Connect (sin SSH)
aws ec2-instance-connect send-ssh-public-key --instance-id i-xxxxx
```

### SSM no funciona

```bash
# Verificar que la instancia tiene IAM Instance Profile
aws ec2 describe-instances --instance-ids i-xxxxx --query 'Reservations[0].Instances[0].IamInstanceProfile'

# Verificar estado de SSM Agent en la instancia
sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service

# Ver logs de SSM Agent
sudo journalctl -u snap.amazon-ssm-agent.amazon-ssm-agent.service -f
```

### Red no funciona

```bash
# Verificar que cloud-init ejecutó
sudo cloud-init status --long

# Ver logs de cloud-init
sudo cat /var/log/cloud-init.log

# Verificar DHCP
sudo dhclient -v

# Verificar netplan
sudo netplan apply
```

---

## 🎯 Resultado Final

**Las VMs exportadas están completamente listas para ser instancias EC2 de primera clase**, con todas las mejores prácticas de AWS aplicadas desde el inicio.

No requieren:
- User Data scripts
- Post-import configuration
- Manual network setup
- Manual SSM Agent installation
- SSH configuration

**Son instancias EC2 nativas desde el momento que arrancan.**
