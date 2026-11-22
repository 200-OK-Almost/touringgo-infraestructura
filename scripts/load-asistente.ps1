param(
    [string]$BaseUrl = "http://localhost:8000",
    [string]$Token = "",
    [Parameter(Mandatory = $true)]
    [string]$ViajeId,
    [int]$NumeroDia = 1,
    [int]$Requests = 20,
    [int]$Concurrency = 5,
    [string]$Message = "Recomendame un café para la tarde"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http

if ($Requests -le 0) {
    throw "Requests debe ser mayor a cero."
}

if ($Concurrency -le 0) {
    throw "Concurrency debe ser mayor a cero."
}

if ([string]::IsNullOrWhiteSpace($Token)) {
    $tokenResponse = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/usuarios/api/usuarios/dev/auth/token"
    $Token = $tokenResponse.accessToken
}

$url = "$BaseUrl/itinerarios/api/viajes/$ViajeId/asistente"
$json = @{
    mensaje = $Message
    numeroDia = $NumeroDia
    historial = @()
} | ConvertTo-Json -Depth 5

$handler = New-Object System.Net.Http.HttpClientHandler
$client = New-Object -TypeName System.Net.Http.HttpClient -ArgumentList $handler
$client.DefaultRequestHeaders.Authorization =
    New-Object -TypeName System.Net.Http.Headers.AuthenticationHeaderValue -ArgumentList "Bearer", $Token

$statuses = @{}
$latencies = New-Object System.Collections.Generic.List[double]
$total = [Diagnostics.Stopwatch]::StartNew()

for ($inicio = 0; $inicio -lt $Requests; $inicio += $Concurrency) {
    $cantidad = [Math]::Min($Concurrency, $Requests - $inicio)
    $lote = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $cantidad; $i++) {
        $contenido = New-Object -TypeName System.Net.Http.StringContent -ArgumentList $json, ([Text.Encoding]::UTF8), "application/json"
        $request = New-Object -TypeName System.Net.Http.HttpRequestMessage -ArgumentList ([System.Net.Http.HttpMethod]::Post), $url
        $request.Content = $contenido
        $cronometro = [Diagnostics.Stopwatch]::StartNew()

        $lote.Add([pscustomobject]@{
            Request = $request
            Task = $client.SendAsync($request)
            Cronometro = $cronometro
        })
    }

    foreach ($item in $lote) {
        $item.Task.Wait()
        $item.Cronometro.Stop()

        $status = [int]$item.Task.Result.StatusCode
        if (-not $statuses.ContainsKey($status)) {
            $statuses[$status] = 0
        }
        $statuses[$status]++

        $latencies.Add($item.Cronometro.Elapsed.TotalMilliseconds)
        $item.Task.Result.Dispose()
        $item.Request.Dispose()
    }
}

$total.Stop()
$client.Dispose()

$ordenadas = $latencies | Sort-Object
$p95Index = [Math]::Min($ordenadas.Count - 1, [Math]::Ceiling($ordenadas.Count * 0.95) - 1)
$p95 = if ($ordenadas.Count -gt 0) { $ordenadas[$p95Index] } else { 0 }
$promedio = if ($ordenadas.Count -gt 0) { ($ordenadas | Measure-Object -Average).Average } else { 0 }
$rps = if ($total.Elapsed.TotalSeconds -gt 0) { $Requests / $total.Elapsed.TotalSeconds } else { 0 }

Write-Host ""
Write-Host "Load test del asistente" -ForegroundColor Cyan
Write-Host "Requests: $Requests Concurrency: $Concurrency"
Write-Host "Duración: $([Math]::Round($total.Elapsed.TotalSeconds, 2)) s"
Write-Host "RPS: $([Math]::Round($rps, 2))"
Write-Host "Promedio: $([Math]::Round($promedio, 1)) ms"
Write-Host "P95: $([Math]::Round($p95, 1)) ms"

$statuses.GetEnumerator() |
    Sort-Object Name |
    ForEach-Object {
        Write-Host "HTTP $($_.Name): $($_.Value)"
    }

if ($statuses.ContainsKey(429)) {
    Write-Warning "Se recibieron respuestas 429 por rate limiting."
}
