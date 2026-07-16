# ===============================================================================
#  verificar_ids_times.ps1
#
#  Consulta a API football-data.org e mostra o ID REAL de cada time do
#  Brasileirao Serie A -- serve para conferir se os IDs que estao
#  hardcoded no tela_config.dart (timesDisponiveis) estao corretos.
#
#  USO: .\verificar_ids_times.ps1
# ===============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$headers = @{ "X-Auth-Token" = "2fe5b44d83914bd5b4b44df54b718fd0" }

Write-Host "Consultando times do Brasileirao Serie A (BSA)..." -ForegroundColor Cyan
try {
    $resp = Invoke-RestMethod -Uri "https://api.football-data.org/v4/competitions/BSA/teams" -Headers $headers
    $resp.teams | Select-Object id, name, shortName, tla | Sort-Object name | Format-Table -AutoSize
} catch {
    Write-Host "Erro ao consultar a API: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Se algum time do seu app (ex: Flamengo, Corinthians, Gremio) nao aparecer" -ForegroundColor Yellow
Write-Host "na lista acima, ele pode nao estar na Serie A nesta temporada -- nesse caso" -ForegroundColor Yellow
Write-Host "use a busca por nome abaixo (troque NOME_DO_TIME):" -ForegroundColor Yellow
Write-Host ""
Write-Host '  $r = Invoke-RestMethod -Uri "https://api.football-data.org/v4/teams?name=NOME_DO_TIME" -Headers $headers' -ForegroundColor DarkGray
Write-Host '  $r.teams | Select-Object id, name, shortName' -ForegroundColor DarkGray
