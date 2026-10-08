# Motor de voz no aparelho (sherpa-onnx): a parte nativa (JNI) lê as classes
# de configuração PELO NOME. Se o R8 renomear ou apagar campos, o app cai ao
# carregar a voz ("ClassNotFoundException: OfflineTtsModelConfig").
-keep class com.k2fsa.sherpa.onnx.** { *; }

# Palavra "Hey Jarvis" (TensorFlow Lite): mesma razão.
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**
