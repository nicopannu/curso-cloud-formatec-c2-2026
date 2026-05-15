# Scripts Locales - CloudCuyo

Scripts para provisionar VMs locales con Vagrant y exportarlas para AWS.

---

## 🔑 Paso 1: Generar SSH Key

Antes de iniciar las VMs, genera la SSH key que se usará para acceso administrativo.

### Bash:
```bash
bash scripts/local/generate-ssh-key.sh
```

### PowerShell:
```powershell
.\scripts\local\generate-ssh-key.ps1
```

**Resultado:**
- Key privada: `C:\clase-redes\lab-key.pem`
- Key pública: `C:\clase-redes\lab-key.pub`
- Copia en proyecto: `lab-key.pub` (usada por Vagrant)

---

## 🚀 Paso 2: Regenerar VMs y Exportar OVAs

Este script hace TODO el proceso automáticamente:

1. Destruye VMs existentes
2. Crea VMs nuevas con:
   - SSM Agent preinstalado
   - Usuario `admin` con password `admin1234`
   - SSH key configurada
3. Exporta OVAs a `C:\Users\Nico\exports-ova\`

### Bash:
```bash
bash scripts/local/regenerate-and-export.sh
```

### PowerShell:
```powershell
.\scripts\local\regenerate-and-export.ps1
```

**Tiempo estimado:** 20-30 minutos

**Resultado:**
```
C:\Users\Nico\exports-ova\
├── cloudcuyo-db01.ova
├── cloudcuyo-api01.ova
├── cloudcuyo-frontend01.ova
├── cloudcuyo-frontend02.ova
└── cloudcuyo-lb01.ova
```

---

## 📤 Paso 3: Subir OVAs a S3

### Bash:
```bash
aws s3 sync /c/Users/Nico/exports-ova/ s3://curso-cloud-c2-2026-ovas/ --acl public-read
```

### PowerShell:
```powershell
aws s3 sync C:\Users\Nico\exports-ova\ s3://curso-cloud-c2-2026-ovas/ --acl public-read
```

---

## 🔐 Acceso a las VMs

### En local (Vagrant):

**Opción 1: Via Vagrant SSH**
```bash
vagrant ssh db01
```

**Opción 2: Via SSH con key**
```bash
ssh -i C:/clase-redes/lab-key.pem cloudadmin@192.168.56.40
```

**Opción 3: Via password**
```bash
ssh cloudadmin@192.168.56.40
# Password: admin1234
```

### En AWS (EC2):

**Opción 1: SSM Session Manager (RECOMENDADO)**
```bash
aws ssm start-session --target i-xxxxxxxxx
```

**Opción 2: SSH con key (si Security Group lo permite)**
```bash
ssh -i C:/clase-redes/lab-key.pem cloudadmin@<ip-publica>
```

---

## 📋 Scripts de provisión individuales

Estos scripts se ejecutan automáticamente por Vagrant:

- `setup-db.sh` - PostgreSQL + SSM Agent + SSH
- `setup-api.sh` - Flask API + SSM Agent + SSH
- `setup-frontend.sh` - NGINX Web + SSM Agent + SSH
- `setup-lb.sh` - NGINX LB + SSM Agent + SSH
- `configure-ssh-access.sh` - Configuración SSH común

---

## ✅ Verificación

### Verificar SSM Agent instalado:
```bash
vagrant ssh db01 -c "snap list | grep amazon-ssm-agent"
```

### Verificar usuario admin:
```bash
vagrant ssh db01 -c "id admin"
```

### Verificar SSH key:
```bash
vagrant ssh db01 -c "cat /home/admin/.ssh/authorized_keys"
```

---

## 🧹 Limpiar y reintentar

Si algo falla:

```bash
# Destruir VMs
vagrant destroy -f

# Borrar exports
rm -rf /c/Users/Nico/exports-ova/*.ova

# Regenerar key si es necesario
bash scripts/local/generate-ssh-key.sh

# Volver a ejecutar
bash scripts/local/regenerate-and-export.sh
```

---

## 📝 Notas importantes

1. **La key NO debe commitearse** al repo (ya está en .gitignore)
2. **SSM Agent** se instala pero NO se inicia en local (se inicia automáticamente en AWS)
3. **Password admin1234** es para desarrollo/labs, NO usar en producción
4. **Los exports pueden tardar** ~20-30 minutos dependiendo del disco
5. **Las VMs deben estar apagadas** para exportar correctamente

---

## 🔒 Seguridad

**Para desarrollo local:**
- ✅ Usuario admin con password
- ✅ SSH key para acceso sin password
- ✅ Password authentication habilitado

**Para producción AWS:**
- ⚠️ Cambiar password de admin
- ⚠️ Usar solo SSM Session Manager
- ⚠️ Deshabilitar password authentication
- ⚠️ Restringir Security Groups
