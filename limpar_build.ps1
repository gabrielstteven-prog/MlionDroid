# ===============================================================================
#  limpar_build.ps1
#
#  Automatiza a limpeza profunda do projeto quando o build do Android fica
#  com cache corrompido (erros estranhos de "arquivo nao encontrado" durante
#  o assembleRelease/assembleDebug que nao fazem sentido com o codigo).
#
#  O que este script faz, em ordem:
#   1. Para processos que costumam travar arquivos do build (Gradle, Java,
#      ADB, Dart) -- essa costuma ser a causa de "nao consigo apagar a pasta"
#   2. Roda flutter clean
#   3. Apaga android\.gradle e android\app\build (cache especifico do projeto)
#   4. Pergunta se voce quer apagar tambem o cache GLOBAL do Gradle (mais
#      forte, mas deixa o proximo build bem mais lento)
#   5. Roda flutter pub get de novo
#
#  USO: rode este script na raiz do projeto (pasta do pubspec.yaml):
#    .\limpar_build.ps1
# ===============================================================================

$ErrorActionPreference = "Continue"

function Escrever($texto, $cor) {
    Write-Host $texto -ForegroundColor $cor
}

# --- 1. Confere se esta na pasta certa ----------------------------------------
if (-not (Test-Path "pubspec.yaml")) {
    Escrever "[ERRO] Nao encontrei o pubspec.yaml aqui. Rode este script na raiz do projeto Flutter." "Red"
    exit 1
}

# --- 2. Para o daemon do Gradle do jeito "educado" primeiro --------------------
Escrever "`n[INFO] Parando o daemon do Gradle..." "Cyan"
if (Test-Path "android\gradlew.bat") {
    Push-Location android
    & .\gradlew.bat --stop 2>$null | Out-Null
    Pop-Location
    Escrever "[OK] Gradle daemon parado." "Green"
} else {
    Escrever "[AVISO] Nao encontrei android\gradlew.bat, pulando esta etapa." "Yellow"
}

# --- 3. Mata processos que costumam travar arquivos do build -------------------
Escrever "`n[INFO] Finalizando processos que podem estar com arquivos abertos (java, adb, dart)..." "Cyan"
$processos = @("java", "adb", "dart")
foreach ($p in $processos) {
    $encontrados = Get-Process -Name $p -ErrorAction SilentlyContinue
    if ($encontrados) {
        $encontrados | Stop-Process -Force -ErrorAction SilentlyContinue
        Escrever "        - $p finalizado." "DarkGray"
    }
}
Start-Sleep -Seconds 2
Escrever "[OK] Processos finalizados." "Green"

# --- 4. flutter clean ------------------------------------------------------------
Escrever "`n[INFO] Rodando flutter clean..." "Cyan"
flutter clean

# --- 5. Apaga as pastas de cache do projeto --------------------------------------
$pastas = @("android\.gradle", "android\app\build", "build")
foreach ($pasta in $pastas) {
    if (Test-Path $pasta) {
        Escrever "[INFO] Apagando $pasta ..." "Cyan"
        try {
            Remove-Item -Recurse -Force $pasta -ErrorAction Stop
            Escrever "[OK] $pasta removida." "Green"
        } catch {
            Escrever "[AVISO] Nao consegui apagar $pasta automaticamente." "Yellow"
            Escrever "        Motivo: $($_.Exception.Message)" "Yellow"
            Escrever "        Tente fechar o VS Code e qualquer explorador de arquivos aberto nessa pasta, e rode o script de novo." "Yellow"
        }
    } else {
        Escrever "[INFO] $pasta ja nao existe, pulando." "DarkGray"
    }
}

# --- 6. Pergunta se quer limpar o cache global do Gradle tambem ----------------
Escrever ""
$limparGlobal = Read-Host "Deseja tambem limpar o cache GLOBAL do Gradle? Isso e compartilhado entre TODOS os projetos Android do seu PC e deixa o proximo build bem mais lento, mas resolve corrupcoes mais teimosas. (s/N)"
if ($limparGlobal -eq "s" -or $limparGlobal -eq "S") {
    $globalCache = "$env:USERPROFILE\.gradle\caches"
    if (Test-Path $globalCache) {
        Escrever "[INFO] Apagando cache global do Gradle em $globalCache ..." "Cyan"
        try {
            Remove-Item -Recurse -Force $globalCache -ErrorAction Stop
            Escrever "[OK] Cache global removido." "Green"
        } catch {
            Escrever "[AVISO] Nao consegui apagar o cache global automaticamente." "Yellow"
            Escrever "        Motivo: $($_.Exception.Message)" "Yellow"
        }
    } else {
        Escrever "[INFO] Cache global nao encontrado em $globalCache, pulando." "DarkGray"
    }
}

# --- 7. Reinstala as dependencias -------------------------------------------------
Escrever "`n[INFO] Rodando flutter pub get..." "Cyan"
flutter pub get

Escrever "`n[OK] Limpeza concluida." "Green"
Escrever "     Agora rode o build de novo, por exemplo: .\publicar_atualizacao.ps1" "Green"