#!/bin/bash
set -e

echo "--- 1. Memperbarui daftar paket Ubuntu ---"
sudo apt-get update

echo "--- 2. [FIX ANDA] Menginstall alat build C (autoconf, libtool, m4) ---"
echo "Ini memperbaiki error 'LT_SYS_SYMBOL_USCORE' saat build libffi."
sudo apt-get install -y \
    build-essential \
    git \
    zip \
    unzip \
    autoconf \
    automake \
    libtool \
    libtool-bin \
    libltdl-dev \
    m4 \
    pkg-config \
    libffi-dev \
    libssl-dev \
    zlib1g-dev \
    lib32ncurses6 \
    lib32z1 \
    python3-pip \
    python3-dev

echo "--- 3. [FIX KITA] Menginstall Java 17 (Wajib untuk Gradle) ---"
sudo apt-get install -y openjdk-17-jdk

echo "--- 4. Menginstall Buildozer via pip ---"
pip install --user buildozer

echo "--- 5. [FIX KITA] Menginstall Cython versi stabil (0.29.x) ---"
echo "Ini untuk menghindari error 'long' di Python 3.10+"
pip install --user "cython==0.29.37"

echo "--- 6. Mengatur JAVA_HOME & PATH secara permanen ---"
echo "" >> ~/.bashrc
echo "# Atur JAVA_HOME ke versi 17 untuk Buildozer" >> ~/.bashrc
echo "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64" >> ~/.bashrc
echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> ~/.bashrc
echo "" >> ~/.bashrc
echo "# Tambahkan pip user install ke PATH" >> ~/.bashrc
echo "export PATH=~/.local/bin:\$PATH" >> ~/.bashrc

echo ""
echo "================================================================"
echo "  ✅ INSTALASI SELESAI"
echo "================================================================"
echo "  Jalankan 'source ~/.bashrc' untuk menerapkan perubahan"
echo "================================================================"