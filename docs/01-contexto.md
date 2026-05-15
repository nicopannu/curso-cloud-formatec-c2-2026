# Contexto del caso CloudCuyo

CloudCuyo es una empresa de servicios cloud, hosting y consultoria tecnologica. Su portal fue construido con una estetica corporativa vintage y opera en una arquitectura on-premise basada en VMs.

## Problema

La arquitectura funciona, pero tiene limitaciones:

- Las VMs se administran manualmente.
- El balanceador Nginx es autogestionado.
- La base de datos depende de una unica VM.
- Los backups no estan automatizados como servicio administrado.
- El buzon de contacto esta acoplado al backend.
- Algunas paginas legacy ya no aportan valor.

## Objetivo de migracion

CloudCuyo quiere llevar el portal a AWS en etapas:

1. Rehost inicial para salir rapido del entorno on-premise.
2. Replatform de componentes operativos como base de datos, balanceo, storage y logs.
3. Refactor progresivo de funcionalidades como el buzon.
4. Retire de contenido obsoleto.
5. Serverless y MLOps para procesos event-driven y clasificacion de mensajes.
