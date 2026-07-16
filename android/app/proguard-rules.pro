# Mantém as classes do Jackson que o SDK do Spotify precisa para funcionar
-keep class com.fasterxml.jackson.databind.** { *; }
-dontwarn com.fasterxml.jackson.databind.**

# Garante que o otimizador não quebre o protocolo de comunicação do Spotify
-keep class com.spotify.protocol.** { *; }
-dontwarn com.spotify.protocol.**