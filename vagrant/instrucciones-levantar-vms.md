# Instrucciones: Levantar VMs localmente con Vagrant

Estas instrucciones son para quienes quieran **levantar el entorno on-premise de CloudCuyo en su propia máquina** usando Vagrant + VirtualBox.

Casos de uso:
- Explorar la arquitectura on-premise antes de migrarla a AWS
- Regenerar los OVAs desde cero (en lugar de usar los ya provistos en S3)
- Desarrollo y pruebas locales de la aplicación

> Para los labs en AWS (Guia 1 y Guia 2) los OVAs ya están disponibles en `s3://curso-cloud-c2-2026-ovas/`. Levantar las VMs localmente es opcional.

---

## Requisitos previos

- **VirtualBox** 7.0+
- **Vagrant** 2.3+
- **4 GB RAM** disponibles
- **10 GB** espacio en disco

---

## Levantar el entorno

Ejecutar desde la carpeta `vagrant/`:

```bash
cd vagrant/
vagrant up
```

Esto crea y provisiona automáticamente 5 VMs:

1. `db01` — PostgreSQL 14 con pgcrypto y datos de prueba
2. `api01` — Flask API + Gunicorn
3. `frontend01` y `frontend02` — NGINX sirviendo el sitio web
4. `lb01` — NGINX load balancer

**Tiempo estimado:** 10-15 minutos (primera vez)

Verificar que todo funciona:

```bash
curl http://192.168.56.10/api/health
curl http://192.168.56.10/api/v1/health
```

Acceder desde el navegador:
- Sitio principal: http://192.168.56.10
- Portal de clientes: http://192.168.56.10/portal.html

### Acceso a las VMs

**Via Vagrant:**
```bash
vagrant ssh db01
vagrant ssh api01
vagrant ssh lb01
```

**Via SSH con key** (una vez generada, ver abajo):
```bash
ssh -i /ruta/a/lab-key.pem cloudadmin@192.168.56.40
```

**Via password:**
```bash
ssh cloudadmin@192.168.56.40
# Password: admin1234
```

### Comandos útiles

```bash
# Apagar VMs (conserva datos)
vagrant halt

# Destruir VMs (limpia todo)
vagrant destroy -f

# Ver estado
vagrant status

# Ver logs de la API
vagrant ssh api01 -c "sudo journalctl -u cloudcuyo-api -f"
```

---

## Regenerar VMs y exportar OVAs

Estos pasos son para el instructor que necesite regenerar los OVAs con SSM Agent, cloud-init y los drivers EC2 preconfigurados para luego subirlos a S3.

### Paso 1: Generar SSH Key (solo una vez)

**Bash:**
```bash
bash ../scripts/local/generate-ssh-key.sh
```

**PowerShell:**
```powershell
..\scripts\local\generate-ssh-key.ps1
```

Genera:
- `lab-key.pem` (clave privada, permisos 400)
- `lab-key.pub` (clave pública, copiada al directorio raíz para Vagrant)

### Paso 2: Regenerar VMs y exportar OVAs

Este script destruye las VMs existentes, las recrea con toda la configuración EC2 y exporta los OVAs:

**Bash:**
```bash
bash ../scripts/local/regenerate-and-export.sh
```

**PowerShell:**
```powershell
..\scripts\local\regenerate-and-export.ps1
```

Lo que hace:
1. `vagrant destroy -f` — Elimina VMs existentes
2. `vagrant up` — Recrea las VMs con:
   - SSM Agent instalado y habilitado
   - cloud-init configurado para EC2
   - Usuario `ssm-user` para SSM Session Manager
   - Usuario `cloudadmin` con SSH key y password
   - Drivers EC2 (ENA, NVMe) verificados
   - Red configurada para DHCP
3. Ejecuta `finalize-for-export.sh` en cada VM (limpieza pre-export)
4. Apaga las VMs
5. Exporta 5 OVAs

**Tiempo estimado:** 25-35 minutos

### Paso 3: Subir OVAs a S3

**Bash:**
```bash
aws s3 sync /ruta/exports-ova/ s3://curso-cloud-c2-2026-ovas/ --acl public-read
```

**PowerShell:**
```powershell
aws s3 sync C:\ruta\exports-ova\ s3://curso-cloud-c2-2026-ovas/ --acl public-read
```

Verificar:
```bash
aws s3 ls s3://curso-cloud-c2-2026-ovas/ --human-readable
```

---

## Notas importantes

- No commitear `lab-key.pem` ni `lab-key.pub` (ya están en `.gitignore`)
- El password `admin1234` es solo para labs educativos
- El SSM Agent **no se inicia** en local — solo funciona en AWS
- Exportar OVAs siempre con las VMs apagadas (el script lo hace automáticamente)
- El bucket S3 debe ser público para que los estudiantes puedan copiar los OVAs sin credenciales

---

## Acceso en AWS (después de importar los OVAs)

**SSM Session Manager (recomendado):**
```bash
aws ssm start-session --target i-xxxxxxxxx
```

**SSH (si el Security Group permite el puerto 22):**
```bash
ssh -i lab-key.pem cloudadmin@<ip-publica-ec2>
```

Ver la guia completa de importación y despliegue en [`../guias/guia-01-rehost-ec2.md`](../guias/guia-01-rehost-ec2.md).
