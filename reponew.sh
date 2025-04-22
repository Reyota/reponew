#!/bin/bash
set -euo pipefail

echo "=== [1] Mengecek dan menginstal paket yang dibutuhkan ==="

PACKAGES=("xz-utils" "curl" "wget")
check_package() { dpkg -l | grep -qw "$1"; }

for pkg in "${PACKAGES[@]}"; do
    if check_package "$pkg"; then
        echo "✓ $pkg sudah terpasang."
    else
        echo "✗ $pkg belum terpasang. Menginstal..."
        sudo apt update
        sudo apt install -y "$pkg"
        check_package "$pkg" && echo "✓ $pkg berhasil diinstal." || echo "✗ Gagal menginstal $pkg."
    fi
done

echo -e "\n=== [2] Input Lokasi Script reponew Saat Ini ==="
read -rp "Masukkan Lokasi Script reponew Saat Ini untuk Contoh Script reponew disimpan di home maka isi '/home': " new_home
read -rp "Masukkan Direktori Tujuan File rsync Contoh disimpan di '/mnt/mirror': " new_mirror

echo -e "\n=== [3] Input Telegram Token dan Chat ID ==="
read -rp "Masukkan Telegram Token: " input_token
read -rp "Masukkan Telegram Chat ID: " input_chatid

if [[ ! -d "$new_mirror" ]]; then
    echo "Direktori $new_mirror belum ada."
    read -rp "Apakah Anda ingin membuatnya? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] && mkdir -p "$new_mirror" && echo "✓ Direktori $new_mirror berhasil dibuat." || exit 1
fi

echo -e "\n=== [4] Update File .sh di mirror-debian dan mirror-ubuntu ==="
script_dirs=("mirror-debian" "mirror-ubuntu")
for dir in "${script_dirs[@]}"; do
    echo "🔍 Mencari file .sh di direktori: $dir"
    sh_files=$(find "$dir" -type f -name "*.sh")
    for file in $sh_files; do
        echo "Memproses $file..."
        sed -i "s|/home|$new_home|g" "$file"
        sed -i "s|/mnt/mirror|$new_mirror|g" "$file"
        sed -i "s|\$token-telegram|$input_token|g" "$file"
        sed -i "s|\$chatid-telegram|$input_chatid|g" "$file"
        echo "✓ $file berhasil diperbarui."
    done
done

# === [5] Proses Debian Config ===
echo -e "\n=== [5] Rename File Config & Update releases/architectures untuk Debian ==="
read -rp "Masukkan Alamat Tujuan Rsync Debian (contoh: mr.heru.id): " new_name_debian

declare -a RELEASES_DEBIAN=()
declare -a ARCHS_DEBIAN=()

while true; do
    read -rp "Masukkan nama release utama Debian (contoh: bullseye): " ver
    RELEASES_DEBIAN+=("$ver" "${ver}-updates" "${ver}-backports" "${ver}-backports-sloppy" "${ver}-proposed-updates")
    read -rp "Ingin menambahkan release Debian lain? (y/n): " again
    [[ "$again" =~ ^[Yy]$ ]] || break
done

while true; do
    read -rp "Masukkan arsitektur Debian (contoh: amd64): " arch
    ARCHS_DEBIAN+=("$arch")
    read -rp "Ingin menambahkan arsitektur Debian lain? (y/n): " again
    [[ "$again" =~ ^[Yy]$ ]] || break
done

RELEASE_LINE_DEBIAN="releases=($(printf "'%s' " "${RELEASES_DEBIAN[@]}"))"
ARCH_LINE_DEBIAN="architectures=($(printf "'%s' " "${ARCHS_DEBIAN[@]}"))"

for filepath in mirror-debian/mirror-debian.d/*; do
    [[ -f "$filepath" ]] || continue
    mv "$filepath" "mirror-debian/mirror-debian.d/$new_name_debian"
    sed -i "s|^releases=.*|$RELEASE_LINE_DEBIAN|" "mirror-debian/mirror-debian.d/$new_name_debian"
    sed -i "s|^architectures=.*|$ARCH_LINE_DEBIAN|" "mirror-debian/mirror-debian.d/$new_name_debian"
    echo "✓ Config Debian diperbarui: $new_name_debian"
done

# === [6] Proses Ubuntu Config ===
echo -e "\n=== [6] Rename File Config & Update releases/architectures untuk Ubuntu ==="
read -rp "Masukkan Alamat Tujuan Rsync Debian (contoh: mr.heru.id): " new_name_ubuntu

declare -a RELEASES_UBUNTU=()
declare -a ARCHS_UBUNTU=()

while true; do
    read -rp "Masukkan nama release utama Ubuntu (contoh: jammy): " ver
    RELEASES_UBUNTU+=("$ver" "${ver}-updates" "${ver}-security" "${ver}-backports" "${ver}-proposed")
    read -rp "Ingin menambahkan release Ubuntu lain? (y/n): " again
    [[ "$again" =~ ^[Yy]$ ]] || break
done

while true; do
    read -rp "Masukkan arsitektur Ubuntu (contoh: amd64): " arch
    ARCHS_UBUNTU+=("$arch")
    read -rp "Ingin menambahkan arsitektur Ubuntu lain? (y/n): " again
    [[ "$again" =~ ^[Yy]$ ]] || break
done

RELEASE_LINE_UBUNTU="releases=($(printf "'%s' " "${RELEASES_UBUNTU[@]}"))"
ARCH_LINE_UBUNTU="architectures=($(printf "'%s' " "${ARCHS_UBUNTU[@]}"))"

for filepath in mirror-ubuntu/mirror-ubuntu.d/*; do
    [[ -f "$filepath" ]] || continue
    mv "$filepath" "mirror-ubuntu/mirror-ubuntu.d/$new_name_ubuntu"
    sed -i "s|^releases=.*|$RELEASE_LINE_UBUNTU|" "mirror-ubuntu/mirror-ubuntu.d/$new_name_ubuntu"
    sed -i "s|^architectures=.*|$ARCH_LINE_UBUNTU|" "mirror-ubuntu/mirror-ubuntu.d/$new_name_ubuntu"
    echo "✓ Config Ubuntu diperbarui: $new_name_ubuntu"
done

echo -e "\n=== [7] Menambahkan Jadwal Crontab ==="

cron_job_ubuntu="0 23 * * * bash $new_home/mirror-ubuntu/mirror-ubuntu.sh"
cron_job_debian="0 0 * * * bash $new_home/mirror-debian/debian-mirror.sh"
cron_job_debian_update="0 1 * * * bash $new_home/mirror-debian/debian-mirror-update.sh"

# Simpan crontab sekarang ke variabel
existing_cron=$(crontab -l 2>/dev/null || true)

# Tambahkan hanya jika belum ada
new_cron="$existing_cron"

[[ "$existing_cron" != *"$cron_job_ubuntu"* ]] && new_cron+=$'\n'"$cron_job_ubuntu"
[[ "$existing_cron" != *"$cron_job_debian"* ]] && new_cron+=$'\n'"$cron_job_debian"
[[ "$existing_cron" != *"$cron_job_debian_update"* ]] && new_cron+=$'\n'"$cron_job_debian_update"

# Tambahkan ke crontab
echo "$new_cron" | crontab -

echo "✓ Jadwal crontab ditambahkan (jika belum ada):"
echo "  • mirror-ubuntu.sh         → 23:00"
echo "  • debian-mirror.sh         → 00:00"
echo "  • debian-mirror-update.sh  → 01:00"


echo -e "\n🎉 Semua proses selesai!"
