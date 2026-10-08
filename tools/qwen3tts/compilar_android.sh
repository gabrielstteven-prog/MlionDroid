#!/usr/bin/env bash
# Compila o motor da voz do Jarvis (Qwen3-TTS em C) para Android arm64 e
# copia para android/app/src/main/jniLibs/arm64-v8a/libqwentts.so.
#
# Origem: https://github.com/gabriele-mastrapasqua/qwen3-tts (MIT), commit ef339be.
# Modelo: Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice (Apache-2.0), baixado pelo app.
# BLAS:   OpenBLAS 0.3.30 (BSD-3).
#
# Ajustes para o Android (feitos no clone, não no repositório original):
#   1. qwen_tts_server.c: o servidor escuta só em 127.0.0.1
#      (.sin_addr.s_addr = htonl(INADDR_LOOPBACK)) — ninguém da rede acessa.
#   2. android_compat.h: o Android não tem pthread_setaffinity_np.
#   3. OpenBLAS com TARGET=CORTEXA57 (o pacote 0.3.30 não traz o kernel do A53).
#
# Uso (Git Bash no Windows, com o NDK 28 instalado pelo Android Studio):
#   bash tools/qwen3tts/compilar_android.sh C:/q3t
set -euo pipefail
BASE="${1:?pasta de trabalho, ex.: C:/q3t}"
SDK="${ANDROID_SDK:-$LOCALAPPDATA/Android/Sdk}"
NDK="$SDK/ndk/28.2.13676358"
BIN="$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin"
CM="$SDK/cmake/3.22.1/bin"
APP="$(cd "$(dirname "$0")/../.." && pwd)"

mkdir -p "$BASE" && cd "$BASE"
[ -d q3 ] || git -c core.longpaths=true clone https://github.com/gabriele-mastrapasqua/qwen3-tts q3
git -C q3 checkout -q ef339be
sed -i 's/\.sin_addr\.s_addr = INADDR_ANY,/.sin_addr.s_addr = htonl(INADDR_LOOPBACK),/' q3/qwen_tts_server.c

if [ ! -f OpenBLAS-0.3.30/build/lib/libopenblas.a ]; then
  curl -sL https://github.com/OpenMathLib/OpenBLAS/releases/download/v0.3.30/OpenBLAS-0.3.30.tar.gz | tar xz
  "$CM/cmake.exe" -G Ninja -S OpenBLAS-0.3.30 -B OpenBLAS-0.3.30/build \
    -DCMAKE_MAKE_PROGRAM="$CM/ninja.exe" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=29 -DTARGET=CORTEXA57 -DBUILD_SINGLE=ON \
    -DNOFORTRAN=1 -DONLY_CBLAS=1 -DBUILD_TESTING=OFF -DBUILD_WITHOUT_LAPACK=ON \
    -DUSE_THREAD=1 -DNUM_THREADS=8 -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=OFF
  "$CM/cmake.exe" --build OpenBLAS-0.3.30/build -j 8
fi
OB="$BASE/OpenBLAS-0.3.30/build"

cd q3
cat > android_compat.h <<'EOF'
#pragma once
#define _GNU_SOURCE 1
#include <pthread.h>
#include <sched.h>
static inline int pthread_setaffinity_np(pthread_t t, size_t n, const cpu_set_t *s) {
    return sched_setaffinity(pthread_gettid_np(t), n, s);
}
EOF
printf '#define QWEN_BUILD_GIT_REV "android"\n#define QWEN_BUILD_SOURCE_FP "android"\n#define QWEN_BUILD_SIMD "neon"\n' > qwen_build_id.h
"$BIN/clang.exe" --target=aarch64-linux-android29 -O3 -march=armv8.2-a+dotprod+fp16 -ffast-math \
  -D_GNU_SOURCE -DQWEN_SIMD_PROFILE=\"neon\" -DUSE_BLAS -DUSE_OPENBLAS -include android_compat.h \
  -I"$OB/generated" -I"$OB" -Ivendor -Ithird_party/ingot/include -Ithird_party/ingot/src \
  -Ithird_party/kleidiai -w -s -o qwen_tts_android \
  main.c qwen_tts_kleidi.c qwen_tts_q8repack.c qwen_tts_q4export.c qwen_tts.c qwen_tts_gguf.c \
  qwen_tts_talker.c qwen_tts_code_predictor.c qwen_tts_speech_decoder.c qwen_tts_kernels.c \
  qwen_tts_dispatch.c qwen_tts_costmap.c qwen_tts_sd_gemm.c qwen_tts_thread.c \
  qwen_tts_kernels_generic.c qwen_tts_kernels_neon.c qwen_tts_kernels_avx.c qwen_tts_audio.c \
  qwen_tts_emotion.c qwen_tts_compose.c qwen_tts_sampling.c qwen_tts_tokenizer.c qwen_json.c \
  qwen_tts_server.c qwen_tts_voice_clone.c qwen_tts_speech_encoder.c vendor/lz4.c \
  third_party/ingot/src/*.c "$OB/lib/libopenblas.a" -lm
cp qwen_tts_android "$APP/android/app/src/main/jniLibs/arm64-v8a/libqwentts.so"
echo "ok: libqwentts.so atualizado"

# Criar a voz (x-vector de 4 KB) a partir de uma gravação de ~25 s, 24 kHz mono:
#   ./qwen_tts -d <Qwen3-TTS-12Hz-0.6B-Base> --ref-audio voz.wav -l Portuguese \
#       --xvector-only --save-voice jarvis.bin --text "Teste." -o /dev/null
#   e copie para assets/vozes/jarvis.bin
