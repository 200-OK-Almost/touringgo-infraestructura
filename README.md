# TouringGo — Infraestructura

Orquestación por `docker compose` de los microservicios de TouringGo (Usuarios, Lugares, Itinerarios), el gateway (YARP) y el frontend.

## Servicios y puertos

| Servicio            | Puerto host | Notas |
| ------------------- | ----------- | ----- |
| `gateway`           | `8000`      | Entry point de todas las APIs (YARP) |
| `frontend`          | `3000`      | Build estático |
| `usuarios-api`      | —           | + `usuarios-db` (host `15431`) |
| `lugares-api`       | —           | + `lugares-db` (host `15432`) |
| `itinerarios-api`   | —           | + `itinerarios-db` (host `15433`) |

Las APIs no exponen puertos al host: se acceden por el gateway:

- `/usuarios/**` → Usuarios
- `/lugares/**` → Lugares
- `/itinerarios/**` → Itinerarios

## Requisitos

- Docker + Docker Compose.
- Los repos hermanos clonados al lado: `touringgo-gateway`, `touringgo-usuarios`, `touringgo-lugares`, `touringgo-itinerarios`, `touringgo-frontend`.

## Arranque

```bash
cp .env.example .env   # completar con valores reales
docker compose up --build
```

Variables de entorno (ver `.env.example`):

| Variable              | Descripción |
| --------------------- | ----------- |
| `GOOGLE_CLIENT_ID`    | OAuth client id de Google |
| `GOOGLE_CLIENT_SECRET`| OAuth client secret de Google |
| `JWT_KEY`             | Clave HS256 en base64 (32 bytes), misma en Usuarios e Itinerarios |
| `FRONTEND_BASE_URL`   | URL del frontend para el callback OAuth (default `http://localhost:5173`) |

## Migraciones

Las tres APIs aplican migraciones EF **automáticamente al arrancar**. No hace falta correr `dotnet ef database update` a mano.

## Recrear bases (importante)

Si hay una migración **destructiva** (cambio de tipo de columna en una clave compuesta, como `PreferenciasCategorias` en Usuarios o `etiquetas_viaje` en Itinerarios), hay que recrear los volúmenes:

```bash
docker compose down -v
docker compose up --build
```

## Validación

Seguir [`SMOKE.md`](./SMOKE.md) para un flujo end-to-end (catálogo, login, crear viaje, generar itinerario, refinar).
