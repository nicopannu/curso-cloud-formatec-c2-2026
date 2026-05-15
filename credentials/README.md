# Credenciales de Acceso - CloudCuyo Labs

## ⚠️ SOLO PARA USO EDUCATIVO

Estas credenciales son públicas y están diseñadas **exclusivamente para laboratorios educativos**.

**NO USAR EN PRODUCCIÓN** - Estas claves y passwords están públicamente disponibles en GitHub.

---

## 🔑 SSH Key

**Ubicación:** `credentials/lab-key.pem`

**Uso:**
```bash
# Copiar key a tu sistema
cp credentials/lab-key.pem /c/clase-redes/lab-key.pem
chmod 400 /c/clase-redes/lab-key.pem

# Conectar a VM local
ssh -i /c/clase-redes/lab-key.pem cloudadmin@192.168.56.40

# Conectar a EC2 en AWS
ssh -i /c/clase-redes/lab-key.pem cloudadmin@<ip-publica-ec2>
```

---

## 👤 Usuario y Password

**Usuario:** `cloudadmin`  
**Password:** `admin1234`

**Uso:**
```bash
# SSH con password
ssh cloudadmin@192.168.56.40
# Password: admin1234

# Sudo sin password
sudo su -
```

---

## 🔐 Método de acceso recomendado en AWS

### Opción 1: SSM Session Manager (RECOMENDADO)

```bash
# Via AWS Console
EC2 > Instancias > Seleccionar > Connect > Session Manager

# Via CLI
aws ssm start-session --target i-xxxxxxxxx
```

**Ventajas:**
- ✅ No requiere puerto 22 abierto
- ✅ Logs centralizados en CloudTrail
- ✅ Control de acceso via IAM
- ✅ Funciona con instancias privadas

### Opción 2: SSH con Key (desarrollo/troubleshooting)

```bash
ssh -i credentials/lab-key.pem cloudadmin@<ip-publica-ec2>
```

**Requisitos:**
- Security Group debe permitir puerto 22
- Instancia debe tener IP pública o usar bastion

---

## 📋 Credenciales de Base de Datos

**PostgreSQL (DB01):**
- Host: `192.168.56.40` (local) o IP privada EC2
- Port: `5432`
- Database: `cloudcuyo`
- User: `cloudcuyo`
- Password: `cloudcuyo`

**Conexión:**
```bash
# Desde dentro de la VM
psql -U cloudcuyo -d cloudcuyo

# Desde otra VM en la misma red
psql -h 192.168.56.40 -U cloudcuyo -d cloudcuyo
```

---

## 🌐 Acceso a servicios

### Local (Vagrant):

| Servicio | URL | Credenciales |
|----------|-----|--------------|
| Load Balancer | http://192.168.56.10 | - |
| Portal Clientes | http://192.168.56.10/portal.html | Ver abajo |
| API | http://192.168.56.30:5000/api/health | - |
| DB | postgresql://192.168.56.40:5432/cloudcuyo | cloudcuyo/cloudcuyo |

### Portal de Clientes (credenciales de prueba):

| Código Cliente | Email |
|----------------|-------|
| `CUST-2018-001` | mrodriguez@bodegasdelvalle.com |
| `CUST-2020-003` | lfernandez@techmza.com |
| `CUST-2021-005` | plopez@cuyoreal.com |

---

## 🔒 Seguridad - Recordatorios

### ✅ Para laboratorios educativos:
- Estas credenciales son públicas por diseño
- Permiten que estudiantes accedan fácilmente
- Facilitan troubleshooting y soporte

### ⚠️ Para entornos reales:
1. **NUNCA** uses estas credenciales en producción
2. **SIEMPRE** genera nuevas keys SSH privadas
3. **CAMBIA** todos los passwords por defecto
4. **USA** AWS Secrets Manager o Parameter Store
5. **IMPLEMENTA** rotación de credenciales
6. **HABILITA** MFA en usuarios IAM
7. **APLICA** principio de menor privilegio

---

## 📚 Referencias

- **Documentación completa:** `docs/lab-01-rehost-total.md`
- **Scripts de provisión:** `scripts/local/`
- **Arquitectura:** `docs/07-arquitectura-completa.md`

---

## 🆘 Troubleshooting

### No puedo conectar con SSH key:

```bash
# Verificar permisos de la key
ls -l /c/clase-redes/lab-key.pem
# Debe ser: -r-------- (400)

# Corregir permisos
chmod 400 /c/clase-redes/lab-key.pem

# Probar con verbose
ssh -vvv -i /c/clase-redes/lab-key.pem cloudadmin@192.168.56.40
```

### No puedo conectar con password:

```bash
# Verificar que SSH permite password authentication
vagrant ssh db01
cat /etc/ssh/sshd_config | grep PasswordAuthentication
# Debe mostrar: PasswordAuthentication yes
```

### SSM no funciona en AWS:

```bash
# Verificar que la instancia tiene el role correcto
aws ec2 describe-instances --instance-ids i-xxx \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'

# Verificar que SSM Agent está registrado
aws ssm describe-instance-information
```

---

## 📧 Soporte

Si tienes problemas con el acceso:
1. Revisa esta documentación
2. Consulta `scripts/local/README.md`
3. Revisa logs: `vagrant ssh db01 -c "sudo journalctl -u sshd -n 50"`
