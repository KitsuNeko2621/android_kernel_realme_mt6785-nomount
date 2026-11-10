#!/bin/bash
 
# Copyright (C) 2023 psionicprjkt
# Revised for local Ubuntu build
 
# ========================
# KONFIGURASI - Edit sesuai kebutuhan
# ========================
KERNEL_DIR="${PWD}"
OUT_DIR="${KERNEL_DIR}/out"
CLANG_DIR="${KERNEL_DIR}/clang"
 
DEFCONFIG="RM6785_defconfig"
JOBS=$(nproc --all)
 
# Warna output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
 
# ========================
# FUNGSI UTILITAS
# ========================
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
 
check_deps() {
    log_info "Memeriksa dependensi sistem..."
    local deps=(git make bc bison flex libssl-dev libelf-dev python3 zip curl wget)
    local missing=()
 
    for dep in "${deps[@]}"; do
        if ! dpkg -s "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
 
    if [ ${#missing[@]} -ne 0 ]; then
        log_warn "Dependensi berikut tidak ditemukan: ${missing[*]}"
        log_info "Menginstall dependensi yang kurang..."
        sudo apt-get update -qq
        sudo apt-get install -y "${missing[@]}" || {
            log_error "Gagal menginstall dependensi. Jalankan manual:"
            echo "  sudo apt-get install -y ${missing[*]}"
            exit 1
        }
    fi
    log_success "Semua dependensi tersedia."
}
 
check_clang() {
    if [ ! -f "${CLANG_DIR}/bin/clang" ]; then
        log_error "Clang tidak ditemukan di: ${CLANG_DIR}/bin/clang"
        echo ""
        echo "Pilihan untuk mendapatkan Clang:"
        echo "  1. Download Clang dari Antman (direkomendasikan):"
        echo "       mkdir -p clang && cd clang"
        echo "       bash <(curl -s https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman) -S=latest"
        echo ""
        echo "  2. Download Clang dari AOSP:"
        echo "       git clone --depth=1 https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r498229 clang"
        echo ""
        exit 1
    fi
    local clang_ver
    clang_ver=$("${CLANG_DIR}/bin/clang" --version | head -n1)
    log_success "Clang ditemukan: ${clang_ver}"
}
 
cleanup() {
    log_info "Membersihkan direktori output sebelumnya..."
    rm -rf "${OUT_DIR}"
    mkdir -p "${OUT_DIR}"
 
    # Selalu jalankan mrproper untuk pastikan source tree bersih
    # (fix: ".. is not clean, please run make mrproper")
    log_info "Menjalankan make mrproper di source tree..."
    make -C "${KERNEL_DIR}" mrproper 2>/dev/null || true
 
    # Hapus manual generated dirs yang kadang tertinggal oleh mrproper
    rm -rf "${KERNEL_DIR}/include/config"
    rm -rf "${KERNEL_DIR}/include/generated"
    rm -f  "${KERNEL_DIR}/.config"
    rm -f  "${KERNEL_DIR}/Module.symvers"
    rm -f  "${KERNEL_DIR}/modules.builtin"
 
    log_success "Source tree dan direktori out siap."
}
 
psionic_compile() {
    # --- Cek environment ---
    check_deps
    check_clang
    cleanup
 
    export ARCH=arm64
    export SUBARCH=arm64
    export KBUILD_BUILD_USER="KitsuNeko"
    export KBUILD_BUILD_HOST="KitsuNeko-PC"
 
    # --- Generate defconfig ---
    log_info "Membuat konfigurasi dari ${DEFCONFIG}..."
    make O="${OUT_DIR}" \
         ARCH=arm64 \
         "${DEFCONFIG}" || {
        log_error "Gagal membuat defconfig!"
        exit 1
    }
    log_success "Defconfig berhasil dibuat."
 
    # --- Compile kernel ---
    log_info "Mulai kompilasi kernel dengan ${JOBS} jobs..."
    echo -e "${YELLOW}======================================${NC}"
 
    BUILD_START=$(date +"%s")
 
    PATH="${CLANG_DIR}/bin:${PATH}" \
    make -j"${JOBS}" \
        O="${OUT_DIR}" \
        LLVM=1 \
        LLVM_IAS=1 \
        ARCH=arm64 \
        CC="clang" \
        LD=ld.lld \
        STRIP=llvm-strip \
        AS=llvm-as \
        AR=llvm-ar \
        NM=llvm-nm \
        OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
        CONFIG_NO_ERROR_ON_MISMATCH=y \
        CFLAGS="-Wno-#pragma-messages" 2>&1 | tee "${KERNEL_DIR}/error.log"
 
    BUILD_END=$(date +"%s")
    BUILD_DIFF=$((BUILD_END - BUILD_START))
 
    echo -e "${YELLOW}======================================${NC}"
 
    # --- Cek hasil build ---
    if [ -f "${OUT_DIR}/arch/arm64/boot/Image.gz-dtb" ]; then
        log_success "Kernel berhasil dikompilasi!"
        log_success "Output: ${OUT_DIR}/arch/arm64/boot/Image.gz-dtb"
        log_info "Waktu kompilasi: $((BUILD_DIFF / 60)) menit $((BUILD_DIFF % 60)) detik"
    elif [ -f "${OUT_DIR}/arch/arm64/boot/Image.gz" ]; then
        log_success "Kernel berhasil dikompilasi!"
        log_success "Output: ${OUT_DIR}/arch/arm64/boot/Image.gz"
        log_info "Waktu kompilasi: $((BUILD_DIFF / 60)) menit $((BUILD_DIFF % 60)) detik"
    else
        log_error "Kompilasi GAGAL! Cek error.log untuk detail:"
        echo "  cat ${KERNEL_DIR}/error.log | grep -i 'error:'"
        exit 1
    fi
}
 
# ========================
# ENTRY POINT
# ========================
psionic_compile
 

