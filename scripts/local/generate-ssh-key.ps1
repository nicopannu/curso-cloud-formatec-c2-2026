# Script PowerShell para generar SSH key para las VMs

$KeyDir = "C:\clase-redes"
$KeyFile = Join-Path $KeyDir "lab-key.pem"
$PubFile = Join-Path $KeyDir "lab-key.pub"
$ProjectPub = ".\lab-key.pub"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Generando SSH Key para CloudCuyo Labs" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Crear directorio si no existe
if (-not (Test-Path $KeyDir)) {
    New-Item -ItemType Directory -Path $KeyDir | Out-Null
}

# Verificar si ya existe
if (Test-Path $KeyFile) {
    Write-Host ""
    $Response = Read-Host "La key $KeyFile ya existe. ¿Sobrescribir? (y/N)"
    if ($Response -ne "y" -and $Response -ne "Y") {
        Write-Host "Usando key existente" -ForegroundColor Green
        exit 0
    }
    Write-Host "Sobrescribiendo key existente..." -ForegroundColor Yellow
}

# Generar nueva key
Write-Host "`nGenerando nueva key RSA 4096 bits..." -ForegroundColor Yellow
ssh-keygen -t rsa -b 4096 -f $KeyFile -N '""' -C "cloudcuyo-lab-key"

# Ajustar permisos (Windows)
icacls $KeyFile /inheritance:r
icacls $KeyFile /grant:r "$($env:USERNAME):(R)"

# Copiar public key al proyecto (para Vagrant)
Copy-Item $PubFile -Destination $ProjectPub

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "✓ SSH Key generada correctamente" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Private key: $KeyFile" -ForegroundColor Cyan
Write-Host "Public key:  $PubFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "La key se usará para acceso SSH a las VMs:" -ForegroundColor Yellow
Write-Host "  - Usuario: cloudadmin"
Write-Host "  - Key: $KeyFile"
Write-Host ""
Write-Host "Ejemplo de conexión:" -ForegroundColor Yellow
Write-Host "  ssh -i $KeyFile admin@<ip-instancia>"
Write-Host ""
Write-Host "Ahora puedes ejecutar: vagrant up" -ForegroundColor Green
