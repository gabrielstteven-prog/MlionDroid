# ===============================================================================
#  publicar_atualizacao.ps1
#
#  Automatiza a publicacao de uma nova versao do MlionDroid Center:
#   1. Calcula a PROXIMA versao automaticamente (ou usa a que voce informar)
#   2. Grava essa versao de volta no pubspec.yaml
#   3. Gera o APK de release (flutter build apk --release)
#   4. Pede o changelog dessa versao (o que mudou)
#   5. Cria a tag + release no GitHub, ja com o .apk anexado
#   6. Apaga TODAS as releases antigas do GitHub -- so fica a que acabou
#      de ser publicada (evita acumular .apk de versoes velhas para sempre)
#
#  PRE-REQUISITO (so uma vez): GitHub CLI instalado e autenticado.
#    winget install --id GitHub.cli
#    gh auth login
#
#  USO NORMAL (versao sobe sozinha, ex: 1.0.0+1 -> 1.0.1+2):
#    .\publicar_atualizacao.ps1
#
#  USO COM VERSAO ESPECIFICA (ex: pular pra uma versao maior):
#    .\publicar_atualizacao.ps1 -Versao 1.1.0
# ===============================================================================

param(
    [string]$Versao = ""
)

$ErrorActionPreference = "Continue"

function Escrever($texto, $cor) {
    Write-Host $texto -ForegroundColor $cor
}

# --- 1. Confere se esta na pasta certa ----------------------------------------
if (-not (Test-Path "pubspec.yaml")) {
    Escrever "[ERRO] Nao encontrei o pubspec.yaml aqui. Rode este script na raiz do projeto Flutter." "Red"
    exit 1
}

# --- 2. Confere se o GitHub CLI esta instalado e autenticado ------------------
$ghInstalado = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghInstalado) {
    Escrever "[ERRO] GitHub CLI ('gh') nao encontrado. Instale com: winget install --id GitHub.cli" "Red"
    exit 1
}
gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Escrever "[ERRO] GitHub CLI nao esta autenticado. Rode: gh auth login" "Red"
    exit 1
}

# --- 3. Calcula a proxima versao e grava no pubspec.yaml -----------------------
$pubspec = Get-Content "pubspec.yaml" -Raw
if (-not ($pubspec -match "version:\s*([\d\.]+)\+(\d+)")) {
    Escrever "[ERRO] Nao consegui ler a linha 'version:' do pubspec.yaml." "Red"
    exit 1
}
$versaoAtual = $Matches[1]
$buildAtual = [int]$Matches[2]

if ([string]::IsNullOrWhiteSpace($Versao)) {
    # Modo automatico: soma 1 no numero de PATCH (o ultimo numero) e no
    # numero de build. Ex: 1.0.0+1 -> 1.0.1+2
    $partesVersao = $versaoAtual -split "\."
    $major = [int]$partesVersao[0]
    $minor = [int]$partesVersao[1]
    $patch = [int]$partesVersao[2]
    $patch++
    $versaoNova = "$major.$minor.$patch"
} else {
    # Modo manual: usa exatamente a versao que voce passou em -Versao
    $versaoNova = $Versao
}
$buildNovo = $buildAtual + 1

Escrever "`n[INFO] Versao atual: $versaoAtual (build $buildAtual)" "DarkGray"
Escrever "[INFO] Nova versao:  $versaoNova (build $buildNovo)" "Cyan"

$linhaVersaoNova = "version: $versaoNova+$buildNovo"
$pubspecNovo = $pubspec -replace "version:\s*[\d\.]+\+\d+", $linhaVersaoNova
Set-Content -Path "pubspec.yaml" -Value $pubspecNovo -NoNewline
Escrever "[OK] pubspec.yaml atualizado para $versaoNova+$buildNovo" "Green"

$versao = $versaoNova
$buildNum = $buildNovo
$tag = "v$versao"
$repo = "gabrielstteven-prog/MlionDroid"
Escrever "[INFO] Tag desta publicacao: $tag" "Cyan"

# --- 4. Confere se essa tag ja existe no GitHub (evita erro de duplicata) -----
# Aqui esperamos que o comando "falhe" quando a tag ainda nao existe (caso
# normal na primeira publicacao) -- por isso desligamos o "parar em erro"
# soh durante essa checagem especifica, e ligamos de novo depois.
$ErrorActionPreference = "SilentlyContinue"
gh release view $tag --repo $repo *> $null
$jaExiste = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = "Continue"

if ($jaExiste) {
    Escrever "`n[AVISO] Ja existe uma release '$tag' publicada no GitHub (coincidencia rara)." "Yellow"
    Escrever "        Rode o script de novo -- a versao ja foi gravada no pubspec.yaml, entao a proxima tentativa usa um numero mais novo." "Yellow"
    exit 1
}

# --- 5. Gera o APK de release ---------------------------------------------------
Escrever "`n[INFO] Gerando APK de release... (pode demorar alguns minutos)" "Cyan"
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Escrever "`n[ERRO] O build falhou. Corrija os erros acima antes de publicar." "Red"
    exit 1
}

$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkPath)) {
    Escrever "[ERRO] APK nao encontrado em $apkPath" "Red"
    exit 1
}
Escrever "[OK] APK gerado com sucesso." "Green"

# --- 6. Gera o changelog automaticamente a partir dos commits do Git -----------
$changelog = ""
$temGit = Test-Path ".git"

# --- 6. Gera o changelog automaticamente a partir dos commits do Git -----------
$changelog = ""
$temGit = Test-Path ".git"

if ($temGit) {
    $ultimaTagLocal = (git describe --tags --abbrev=0 2>$null)
    if ($ultimaTagLocal) { $ultimaTagLocal = $ultimaTagLocal.Trim() }

    if ($LASTEXITCODE -eq 0 -and $ultimaTagLocal) {
        Escrever "[INFO] Ultima tag local encontrada: $ultimaTagLocal" "DarkGray"
        $commits = git log "$ultimaTagLocal..HEAD" --pretty=format:"- %s" 2>&1
    } else {
        # Nenhuma tag local ainda -- pega todo o historico existente
        Escrever "[INFO] Nenhuma tag local encontrada -- usando todo o historico." "DarkGray"
        $commits = git log --pretty=format:"- %s" 2>&1
    }
    $codigoSaidaGitLog = $LASTEXITCODE

    # $commits pode vir como uma unica string OU como array de linhas,
    # dependendo de quanto texto o Git devolveu -- -join trata os dois
    # casos igual, sem risco de quebrar o texto sem querer.
    $textoCapturado = ($commits -join "`n").Trim()

    if ($codigoSaidaGitLog -ne 0) {
        # O comando falhou de verdade -- mostra o motivo em vez de
        # publicar uma mensagem de erro como se fosse changelog.
        Escrever "`n[AVISO] git log falhou ao gerar o changelog automatico:" "Yellow"
        Escrever "         $textoCapturado" "Yellow"
    } elseif ($textoCapturado) {
        $changelog = $textoCapturado
        Escrever "`n[INFO] Changelog gerado automaticamente a partir do Git:" "Cyan"
        Escrever $changelog "DarkGray"
    } else {
        Escrever "`n[AVISO] Nenhum commit novo encontrado no Git desde a ultima tag." "Yellow"
        Escrever "         (tag usada na comparacao: '$ultimaTagLocal')" "Yellow"
    }
} else {
    Escrever "`n[AVISO] Esta pasta ainda nao e um repositorio Git." "Yellow"
    Escrever "         Rode 'git init' para habilitar changelog automatico nas proximas vezes." "Yellow"
}

# Sem Git configurado (ou sem commits novos): pede na mao, como antes.
if ([string]::IsNullOrWhiteSpace($changelog)) {
    Escrever "`n[INFO] Digite as novidades desta versao (uma linha por novidade)." "Yellow"
    Escrever "       Pressione Enter numa linha vazia para terminar:" "Yellow"
    $linhas = @()
    while ($true) {
        $linha = Read-Host
        if ([string]::IsNullOrWhiteSpace($linha)) { break }
        $linhas += "- $linha"
    }
    $changelog = $linhas -join "`n"
    if ([string]::IsNullOrWhiteSpace($changelog)) {
        $changelog = "Nova versao $versao."
    }
}

# --- 7. Publica a release no GitHub, ja com o APK anexado ----------------------
Escrever "`n[INFO] Publicando $tag no GitHub..." "Cyan"
gh release create $tag $apkPath --repo $repo --title "Versao $versao" --notes "$changelog"
$publicacaoOk = ($LASTEXITCODE -eq 0)

# Marca essa versao no historico local do Git, para a proxima publicacao
# saber exatamente de onde comecar a contar os commits novos. Isso roda
# DEPOIS de guardar $publicacaoOk, pra nao atrapalhar a checagem abaixo.
if ($temGit -and $publicacaoOk) {
    git tag $tag 2>$null | Out-Null
}

if ($publicacaoOk) {
    Escrever "`n[OK] Publicado com sucesso!" "Green"
    Escrever "     O banner de atualizacao vai aparecer sozinho pros seus amigos na proxima vez que abrirem o app." "Green"

    # --- 8. Apaga releases antigas, mantem so a que acabou de ser publicada ---
    Escrever "`n[INFO] Limpando versoes antigas do GitHub (mantendo so a $tag)..." "Cyan"
    $todasAsTags = gh release list --repo $repo --json tagName --jq ".[].tagName"

    if ($LASTEXITCODE -eq 0 -and $todasAsTags) {
        $tagsAntigas = $todasAsTags -split "`n" | Where-Object {
            $_.Trim() -ne "" -and $_.Trim() -ne $tag
        }

        if ($tagsAntigas.Count -eq 0) {
            Escrever "[INFO] Nenhuma versao antiga para apagar." "DarkGray"
        } else {
            foreach ($tagAntiga in $tagsAntigas) {
                $tagAntiga = $tagAntiga.Trim()
                Escrever "        Apagando $tagAntiga ..." "DarkGray"
                gh release delete $tagAntiga --repo $repo --yes --cleanup-tag *> $null
            }
            Escrever "[OK] $($tagsAntigas.Count) versao(oes) antiga(s) removida(s). So a $tag ficou disponivel." "Green"
        }
    } else {
        Escrever "[AVISO] Nao consegui listar as releases antigas para limpar. Publicacao em si ja foi feita normalmente." "Yellow"
    }
} else {
    Escrever "`n[ERRO] Algo deu errado ao publicar a release." "Red"
}