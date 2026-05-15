# Inventario on-premise

| Componente | Hostname | IP | Tecnologia | Puerto | Dependencias |
|---|---|---|---|---|---|
| Reverse proxy | lb01 | 192.168.56.10 | Ubuntu + Nginx | 80 | frontend01, api01 |
| Frontend | frontend01 | 192.168.56.20 | Ubuntu + Nginx | 80 | api01 |
| Backend API | api01 | 192.168.56.30 | Ubuntu + Flask | 5000 | db01 |
| Base de datos | db01 | 192.168.56.40 | Ubuntu + PostgreSQL | 5432 | storage local |

## Puertos relevantes

| Origen | Destino | Puerto | Motivo |
|---|---|---|---|
| Host | lb01 | 80 | Acceso al portal |
| lb01 | frontend01 | 80 | Sitio web |
| lb01 | api01 | 5000 | API |
| api01 | db01 | 5432 | Base de datos |

