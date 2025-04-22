# 🌀 Auto Mirror Setup Script

Script Bash ini dibuat untuk **mengatur otomatisasi pengaturan mirror Debian & Ubuntu**, termasuk:
- Instalasi dependensi,
- Penyesuaian path direktori,
- Penyesuaian token Telegram,
- Pengubahan file konfigurasi release dan arsitektur,
- Penjadwalan `cron` untuk menjalankan script sync mirror secara berkala.

---

## 📦 Fitur

- ✅ Cek dan install paket: `xz-utils`, `curl`, `wget`
- 🔧 Update otomatis isi file `.sh` berdasarkan direktori dan token yang diinput
- 📁 Rename dan modifikasi file konfigurasi Debian & Ubuntu
- 🔁 Penambahan release dan arsitektur custom
- ⏰ Penjadwalan cron otomatis:
  - `mirror-ubuntu.sh` dijalankan setiap **23:00**
  - `debian-mirror.sh` dijalankan setiap **00:00**
  - `debian-mirror-update.sh` dijalankan setiap **01:00**

---

## 🚀 Cara Menggunakan

1. Clone atau salin script ini ke server/VPS Anda.
2. Jalankan script dengan hak akses eksekusi:

   ```bash
   chmod +x setup-mirror.sh
   ./setup-mirror.sh
3. Ikuti setiap pertanyaan/interaktif input:
- Lokasi direktori script
- Path tujuan mirror (contoh: /mnt/mirror)
- Telegram Token & Chat ID
- Nama rsync config untuk Debian & Ubuntu
- Release & arsitektur yang diinginkan
4. Setelah selesai, semua pengaturan akan diperbarui dan cron akan ditambahkan.
