# ===============================================================================
#  verificar_ids_times.ps1
#
#  Lista o ID ESPN de cada time (Serie A e Serie B) -- serve para conferir ou
#  adicionar times em lib/times.dart (campo espnId). API publica, sem chave.
#
#  USO: .\verificar_ids_times.ps1
# ===============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

foreach ($liga in @(@{cod = "bra.1"; nome = "Serie A"}, @{cod = "bra.2"; nome = "Serie B"})) {
    Write-Host "`nTimes da $($liga.nome) ($($liga.cod)):" -ForegroundColor Cyan
    try {
        $resp = Invoke-RestMethod -Uri "https://site.api.espn.com/apis/site/v2/sports/soccer/$($liga.cod)/teams" -TimeoutSec 20
        $resp.sports[0].leagues[0].teams |
            ForEach-Object { [pscustomobject]@{ espnId = $_.team.id; nome = $_.team.displayName } } |
            Sort-Object nome | Format-Table -AutoSize
    } catch {
        Write-Host "Erro ao consultar a ESPN: $($_.Exception.Message)" -ForegroundColor Red
    }
}
