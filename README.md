# MlionDroid Center

Painel inteligente para tablet: fica ligado o dia todo, revezando telas de
clima, futebol, notícias, agenda, lista de compras, fotos e música.

## Telas

| Tela | O que mostra | Fonte dos dados |
|---|---|---|
| Bom Dia | Saudação, clima do dia, foto do dia, notícia e frase (só de manhã) | Open-Meteo, G1, fotos do app |
| Clima | Temperatura, previsão de 4 dias, alerta de chuva e radar | Open-Meteo + Windy |
| Time | Notícias do time + posição, último resultado e próximo jogo | ge.globo (RSS) + ESPN |
| Próxima Partida | Data, horário, estádio, **onde assistir**, placar ao vivo, últimos 5 jogos | ESPN + futebolnatv.com.br |
| Classificação | Brasileirão e grupos da Libertadores | ESPN |
| Calendário | Eventos do Google Agenda e tarefas do Google Tasks | Google |
| Compras | Lista "Compras" do Google Tasks, com desfazer e adição por voz | Google |
| Brasil / Região | Notícias por categoria e por cidade (filtro real pelo texto) | G1 (RSS) |
| Memórias | Slideshow das fotos adicionadas ao app | Pasta privada do app |
| Spotify | Música tocando agora (aparece sozinha ao trocar de faixa) | Spotify Web API |
| Modo Noite | Relógio escuro com brilho reduzido de madrugada | — |

Nenhuma API paga ou chave secreta é necessária. O Spotify usa o Client ID
do próprio usuário (configurado no app).

## Estrutura do código

```
lib/
  main.dart              rodízio de telas, modo manual, Modo Noite
  rodizio.dart           lógica pura do rodízio (testada)
  config_manager.dart    configurações (JSON local)
  cache_manager.dart     cache com "último dado conhecido" para funcionar sem internet
  services/              busca de dados (uma fonte de verdade por assunto)
    weather_service.dart   clima (uma chamada para barra, Clima e Bom Dia)
    football_service.dart  jogos, resultados e tabelas (ESPN)
    tv_service.dart        canais de transmissão (futebolnatv)
    news_service.dart      RSS, remoção de duplicadas, filtro por cidade
    google_auth_service.dart  login Google compartilhado (silencioso no rodízio)
    fotos_service.dart     fotos na pasta privada do app
  widgets/tela_noticias.dart  tela de notícias reutilizada por Time, Brasil e Região
  tela_*.dart            telas
  times.dart             times disponíveis (IDs ESPN, cores, escudos)
test/                    testes com respostas reais salvas em test/fixtures
```

## Desenvolvimento

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

## Publicar uma atualização

```powershell
.\publicar_atualizacao.ps1
```

O script sobe a versão, gera o APK, publica no GitHub Releases e o app dos
tablets mostra o ícone de atualização. **Escreva mensagens de commit
descritivas** — elas viram o "O que há de novo" que aparece no tablet.

## Chave de assinatura (importante)

Todas as versões publicadas até hoje foram assinadas com a chave de debug
deste PC (`%USERPROFILE%\.android\debug.keystore`). O Android só instala
uma atualização por cima se ela tiver **a mesma assinatura**. Se esse
arquivo se perder (formatação, PC novo), nenhum tablet consegue atualizar
sem desinstalar o app — e o login Google também para (depende do SHA-1).

Faça uma vez:

```powershell
mkdir android\keystore
copy $env:USERPROFILE\.android\debug.keystore android\keystore\mliondroid-release.keystore
```

Crie `android\key.properties` com:

```
storeFile=../keystore/mliondroid-release.keystore
storePassword=android
keyAlias=androiddebugkey
keyPassword=android
```

Os dois ficam fora do git (`.gitignore`). **Guarde uma cópia do arquivo
`.keystore` fora deste PC** (pendrive, nuvem). Sem `key.properties`, o
build cai automaticamente na chave de debug do PC.
