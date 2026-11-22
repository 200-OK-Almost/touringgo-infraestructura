# Smoke test — integración end-to-end

Flujo completo contra el gateway en `http://localhost:8000`. Requiere `.env` con `GOOGLE_CLIENT_ID/SECRET` y `JWT_KEY` (base64, 32 bytes).

## 1. Recrear bases

Necesario si hubo migraciones destructivas (Usuarios `PreferenciasCategorias`, Itinerarios `etiquetas_viaje`).

```powershell
docker compose down -v
docker compose up --build -d
docker compose ps   # esperar a que los servicios estén healthy
```

## 2. Verificar migraciones al arrancar

```powershell
docker compose logs itinerarios-api | Select-String -Pattern "error|fail|exception"
docker compose logs usuarios-api     | Select-String -Pattern "error|fail|exception"
docker compose logs lugares-api      | Select-String -Pattern "error|fail|exception"
```

No debe haber errores: cada API aplica su `MigrateAsync` sin excepción.

## 3. Catálogo de Lugares (filtro OR por lista)

```powershell
curl.exe "http://localhost:8000/lugares/api/lugares?tamano=3"
curl.exe "http://localhost:8000/lugares/api/lugares?barrio=Palermo&categoriaCodigo=cafe_especialidad&categoriaCodigo=parques_aire_libre"
```

Esperado: `items` con `categorias` como **códigos** (strings); el segundo trae lugares que matchean **cualquiera** de los dos códigos.

## 4. Token dev (Usuarios)

```powershell
curl.exe -X POST "http://localhost:8000/usuarios/api/usuarios/dev/auth/token"
```

Esperado: `{ "accessToken": "...", "expiresAt": "..." }`.

```powershell
$token = (Invoke-RestMethod -Method Post -Uri "http://localhost:8000/usuarios/api/usuarios/dev/auth/token").accessToken
```

## 5. Verificar JWT en Itinerarios

```powershell
curl.exe -i "http://localhost:8000/itinerarios/api/viajes"                                  # → 401
curl.exe -i "http://localhost:8000/itinerarios/api/viajes" -H "Authorization: Bearer $token" # → 200
```

## 6. Crear viaje (contrato: `categoriaCodigos`)

```powershell
curl.exe -i -X POST "http://localhost:8000/itinerarios/api/viajes" `
  -H "Authorization: Bearer $token" `
  -H "Content-Type: application/json" `
  -d '{"titulo":"Salida Palermo","tipoViaje":"Solo","barrio":"Palermo","alcanceTemporal":"DiaCompleto","nivelPresupuesto":"Equilibrado","ritmoCaminata":"Activo","tipoPuntoPartida":"NodoUrbano","nombrePuntoPartida":"Plaza Italia","direccionPartida":"Av. Sarmiento 2701","latitudPartida":-34.5815,"longitudPartida":-58.4214,"categoriaCodigos":["cafe_especialidad","parques_aire_libre","museos_galerias"]}'
```

Esperado: **201** con `estado: "Borrador"`, `categoriaCodigos` (3) y `codigoInvitacion`. Guardar el `id`.

## 7. Generar itinerario (llama a Lugares por HTTP)

```powershell
curl.exe -i -X POST "http://localhost:8000/itinerarios/api/viajes/<ID>/itinerario" -H "Authorization: Bearer $token"
```

Esperado: **200**, array de itinerarios con `paradas` cuyo `turno` va **por orden** (`Manana`, `Tarde`, `Noche` según alcance). El viaje pasa a `Planificado`.

## 8. Obtener itinerario

```powershell
curl.exe -i "http://localhost:8000/itinerarios/api/viajes/<ID>/itinerario" -H "Authorization: Bearer $token"
```

## 9. Refinar

```powershell
curl.exe -i -X POST "http://localhost:8000/itinerarios/api/viajes/<ID>/refinar" `
  -H "Authorization: Bearer $token" -H "Content-Type: application/json" `
  -d '{"tipo":"MasEconomico"}'
```

## 10. Sugerencias de turno libre

```powershell
curl.exe -i -X POST "http://localhost:8000/itinerarios/api/viajes/<ID>/sugerencias-turnos-libres" `
  -H "Authorization: Bearer $token" -H "Content-Type: application/json" `
  -d '{}'
```

## 11. Asistente RAG — smoke E2E

El script crea un viaje, genera el itinerario, consulta capacidades, prueba una consulta, una aclaración y, opcionalmente, aplica una recomendación.

```powershell
cd C:\Proyecto\touringgo-infraestructura
.\scripts\smoke-asistente.ps1 -Aplicar
```

Para conservar el viaje y usar su ID en el load test:

```powershell
$smoke = .\scripts\smoke-asistente.ps1 -Aplicar -KeepViaje
$smoke.ViajeId
```

Sin `-Aplicar` el smoke no muta itinerarios. El script elimina el viaje creado salvo que se use `-KeepViaje`.

Checkpoints:

- capacidades devuelve `habilitado: true`;
- la consulta devuelve recomendaciones;
- con 2+ paradas, la aclaración devuelve opciones;
- con `-Aplicar`, el endpoint de aplicar devuelve `200`.

## 12. Asistente RAG — load test

Requiere un `ViajeId` válido. Se puede reutilizar el de un smoke con `-KeepViaje`.

```powershell
cd C:\Proyecto\touringgo-infraestructura
.\scripts\load-asistente.ps1 -ViajeId "<ID>" -Requests 20 -Concurrency 5
```

El script informa:

- RPS;
- latencia promedio y P95;
- conteo por status HTTP;
- advertencia si aparece `429`.

Para probar rate limiting, subir `Requests` por encima de `Asistente:RateLimit:PermitLimitPorViaje`.

## 13. Ollama off/on

Con Ollama deshabilitado el smoke debe seguir funcionando mediante reglas y fallback determinista:

```yaml
Asistente__LlmEnabled: "false"
Asistente__LlmGenerarMensaje: "false"
```

Con Ollama habilitado y disponible se pueden probar intención y generación:

```yaml
Asistente__LlmEnabled: "true"
Asistente__LlmGenerarMensaje: "true"
```

Si Ollama no responde, el asistente no debe fallar: debe usar el fallback y registrar `llm_error`/`llm_timeout`.

## Checkpoints

- Paso 5: **401** sin token / **200** con token.
- Paso 3: `categorias` de Lugares son c��digos y el OR por lista funciona.
- Paso 6: acepta `categoriaCodigos` (mandar `categoriaIds` ��' 400).
- Paso 7: `paradas` con turno por orden (no depende del turno del lugar).
- Asistente: capacidades, consulta, aclaración y aplicar responden según contrato.
- Load test: sin `500` inesperados; `429` solo al superar el límite.
