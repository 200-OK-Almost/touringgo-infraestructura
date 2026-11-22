param(
    [string]$BaseUrl = "http://localhost:8000",
    [string]$Token = "",
    [string]$ViajeId = "",
    [int]$NumeroDia = 1,
    [switch]$Aplicar,
    [switch]$KeepViaje
)

$ErrorActionPreference = "Stop"

function Write-Paso([string]$mensaje) {
    Write-Host ""
    Write-Host "== $mensaje ==" -ForegroundColor Cyan
}

function Invoke-ApiPost([string]$uri, [string]$json) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)

    return Invoke-RestMethod `
        -Method Post `
        -Uri $uri `
        -Headers $headers `
        -ContentType "application/json; charset=utf-8" `
        -Body $bytes
}

function Invoke-ApiGet([string]$uri) {
    return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    Write-Paso "Token de desarrollo"
    $tokenResponse = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/usuarios/api/usuarios/dev/auth/token"
    $Token = $tokenResponse.accessToken

    if ([string]::IsNullOrWhiteSpace($Token)) {
        throw "No se pudo obtener el token de desarrollo."
    }
}

$headers = @{ Authorization = "Bearer $Token" }
$viajeCreado = $false

try {
    $viajeIdActual = $ViajeId

    Write-Paso "Capacidades del asistente"
    $capacidades = Invoke-ApiGet "$BaseUrl/itinerarios/api/viajes/asistente/capacidades"

    if (-not $capacidades.habilitado) {
        throw "El asistente está deshabilitado en el entorno."
    }

    Write-Host "Asistente habilitado. TopK=$($capacidades.limites.topK) MaxHistorial=$($capacidades.limites.maxHistorial)"

    if ([string]::IsNullOrWhiteSpace($viajeIdActual)) {
        Write-Paso "Crear viaje de smoke"

        $viajeJson = @{
            titulo = "Smoke asistente $(Get-Date -Format 'HHmmss')"
            tipoViaje = "Solo"
            barrio = "Palermo"
            alcanceTemporal = "DiaCompleto"
            nivelPresupuesto = "Equilibrado"
            ritmoCaminata = "Activo"
            tipoPuntoPartida = "NodoUrbano"
            nombrePuntoPartida = "Plaza Italia"
            direccionPartida = "Av. Sarmiento 2701"
            latitudPartida = -34.5815
            longitudPartida = -58.4214
            categoriaCodigos = @("cafe_especialidad", "parques_aire_libre", "museos_galerias")
        } | ConvertTo-Json -Depth 5

        $viaje = Invoke-ApiPost "$BaseUrl/itinerarios/api/viajes" $viajeJson
        $viajeIdActual = $viaje.id.ToString()
        $viajeCreado = $true

        Write-Host "Viaje creado: $viajeIdActual"

        Write-Paso "Generar itinerario"
        Invoke-ApiPost "$BaseUrl/itinerarios/api/viajes/$viajeIdActual/itinerario" "{}" | Out-Null
    }

    Write-Paso "Obtener itinerario"
    $itinerarios = Invoke-ApiGet "$BaseUrl/itinerarios/api/viajes/$viajeIdActual/itinerario"
    $itinerario = $itinerarios | Where-Object { $_.numeroDia -eq $NumeroDia } | Select-Object -First 1

    if ($null -eq $itinerario) {
        throw "No se encontró el día $NumeroDia en el itinerario."
    }

    $version = $itinerario.version
    $paradas = @($itinerario.paradas)

    Write-Host "Versión=$version Paradas=$($paradas.Count)"

    Write-Paso "Consulta al asistente"
    $consultaJson = @{
        mensaje = "Recomendame un café para la tarde"
        numeroDia = $NumeroDia
        historial = @()
    } | ConvertTo-Json -Depth 5

    $consulta = Invoke-ApiPost "$BaseUrl/itinerarios/api/viajes/$viajeIdActual/asistente" $consultaJson

    Write-Host "Mensaje: $($consulta.mensaje)"
    Write-Host "Recomendaciones: $(@($consulta.recomendaciones).Count) PuedeAplicar=$($consulta.puedeAplicar)"

    if (@($consulta.recomendaciones).Count -eq 0) {
        Write-Warning "La consulta no devolvió recomendaciones."
    }

    Write-Paso "Aclaración"
    if ($paradas.Count -ge 2) {
        $aclaracionJson = @{
            mensaje = "Reemplazá la parada por un bar"
            numeroDia = $NumeroDia
            historial = @()
        } | ConvertTo-Json -Depth 5

        $aclaracion = Invoke-ApiPost "$BaseUrl/itinerarios/api/viajes/$viajeIdActual/asistente" $aclaracionJson

        if ($null -eq $aclaracion.aclaracion) {
            throw "Se esperaba una aclaración y el backend no la devolvió."
        }

        Write-Host "Aclaración: $($aclaracion.aclaracion.pregunta) Opciones=$(@($aclaracion.aclaracion.opciones).Count)"
    } else {
        Write-Warning "Se necesitan al menos 2 paradas para probar la aclaración."
    }

    if ($Aplicar) {
        Write-Paso "Aplicar recomendación"

        if (@($consulta.recomendaciones).Count -eq 0) {
            throw "No hay recomendaciones para aplicar."
        }

        if ([string]::IsNullOrWhiteSpace($version)) {
            throw "El itinerario no tiene versión para aplicar."
        }

        $lugarId = $consulta.recomendaciones[0].lugarId

        if ($paradas.Count -gt 0) {
            $tipoAccion = "ReemplazarParada"
            $paradaId = $paradas[0].id
        } else {
            $tipoAccion = "AgregarParada"
            $paradaId = $null
        }

        $aplicarJson = @{
            tipo = $tipoAccion
            numeroDia = $NumeroDia
            lugarId = $lugarId
            paradaId = $paradaId
            turno = $null
            version = $version
        } | ConvertTo-Json -Depth 5

        $aplicado = Invoke-ApiPost "$BaseUrl/itinerarios/api/viajes/$viajeIdActual/asistente/aplicar" $aplicarJson
        Write-Host "Aplicar OK. Itinerarios devueltos: $(@($aplicado).Count)"
    } else {
        Write-Warning "Aplicar omitido. Usar -Aplicar para ejecutarlo."
    }

    Write-Host ""
    Write-Host "Smoke del asistente OK." -ForegroundColor Green

    [pscustomobject]@{
        ViajeId = $viajeIdActual
        Version = $version
        Recomendaciones = @($consulta.recomendaciones).Count
        Aplicado = [bool]$Aplicar
    }
}
finally {
    if ($viajeCreado -and -not $KeepViaje) {
        try {
            Invoke-RestMethod `
                -Method Delete `
                -Uri "$BaseUrl/itinerarios/api/viajes/$viajeIdActual" `
                -Headers $headers | Out-Null
            Write-Host "Viaje de smoke eliminado."
        } catch {
            Write-Warning "No se pudo eliminar el viaje de smoke: $($_.Exception.Message)"
        }
    }
}
