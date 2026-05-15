# Script PowerShell para regenerar VMs y exportar OVAs

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Regenerando VMs con SSM Agent" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Destruir VMs existentes
Write-Host "`n1. Destruyendo VMs existentes..." -ForegroundColor Yellow
vagrant destroy -f

# Recrear VMs con nuevos scripts
Write-Host "`n2. Creando VMs con SSM Agent preinstalado..." -ForegroundColor Yellow
vagrant up

Write-Host "`n3. Esperando 30 segundos para que las VMs se estabilicen..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

Write-Host "`n4. Finalizando preparación de VMs para export..." -ForegroundColor Yellow
$VMs = @("db01", "api01", "frontend01", "frontend02", "lb01")

foreach ($vm in $VMs) {
    Write-Host "Finalizando ${vm}..." -ForegroundColor Yellow
    vagrant ssh $vm -c "sudo bash /vagrant/scripts/local/finalize-for-export.sh"
}

# Crear directorio de exports si no existe
$ExportDir = "C:\Users\Nico\exports-ova"
if (-not (Test-Path $ExportDir)) {
    New-Item -ItemType Directory -Path $ExportDir | Out-Null
}

Write-Host "`n5. Apagando VMs para exportar..." -ForegroundColor Yellow
vagrant halt

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "Exportando OVAs" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Eliminar OVAs previos si existen
Remove-Item -Path (Join-Path $ExportDir "*.ova") -Force -ErrorAction SilentlyContinue

# Exportar cada VM

foreach ($vm in $VMs) {
    Write-Host "`nExportando cloudcuyo-${vm}..." -ForegroundColor Yellow
    $OutputFile = Join-Path $ExportDir "cloudcuyo-${vm}.ova"
    VBoxManage export $vm -o $OutputFile --ovf20 --manifest
    Write-Host "✓ cloudcuyo-${vm}.ova exportado" -ForegroundColor Green
}

Write-Host "`n=========================================" -ForegroundColor Green
Write-Host "✓ Proceso completado" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green

Write-Host "`nOVAs exportados en: $ExportDir" -ForegroundColor Cyan
Get-ChildItem -Path $ExportDir -Filter *.ova | Format-Table Name, @{Label="Size (MB)"; Expression={[math]::Round($_.Length/1MB, 2)}}

Write-Host "`nAhora puedes:" -ForegroundColor Yellow
Write-Host "1. Subir los OVAs a S3: aws s3 sync $ExportDir s3://curso-cloud-c2-2026-ovas/ --acl public-read"
Write-Host "2. O iniciar Vagrant de nuevo: vagrant up"
