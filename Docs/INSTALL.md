# Memasang Nubi untuk pemakaian pribadi

Paket ini berisi aplikasi native macOS 14 atau lebih baru. Xcode tidak diperlukan untuk menjalankan aplikasi yang sudah dibangun.

1. Ekstrak ZIP, lalu tutup Nubi yang sedang berjalan melalui menu bar → Quit. Isi file shelf akan dikosongkan; file aslinya tetap ada.
2. Salin `Nubi.app` ke `~/Applications` atau `/Applications`. Gunakan satu lokasi tetap dan jalankan salinan tersebut.
3. Nubi tampil di bagian atas layar dan menu bar, tanpa ikon Dock. Buka Settings melalui menu bar atau ikon roda gigi pada notch.
4. Putar lagu di Music atau Spotify. Saat macOS meminta izin Automation, izinkan akses ke player yang ingin dipakai. Deteksi otomatis aktif secara default.
5. Jika ingin aplikasi berjalan saat masuk ke macOS, aktifkan Launch at login dari salinan yang sudah dipasang. Periksa System Settings → General → Login Items bila persetujuan diperlukan.

## Memperbarui

Tutup aplikasi sebelum mengganti salinan di lokasi pemasangan yang sama. Preferensi tersimpan terpisah dan tidak dihapus saat mengganti bundle aplikasi. Build lokal memakai tanda tangan ad-hoc; macOS mungkin meminta ulang izin Automation setelah pembaruan. Jika login item tidak lagi bekerja, nonaktifkan lalu aktifkan kembali Launch at login dari salinan terpasang.

Jika beralih dari versi bernama `Notch.app`, jalankan `Nubi.app` terlebih dahulu dan periksa fitur serta izin. Identitas `com.personal.notch` tetap dipakai agar preferensi lama terbaca. Setelah itu, tutup dan pindahkan salinan lama `Notch.app` ke Trash agar hanya satu aplikasi aktif; periksa ulang Launch at login.

## Jika musik belum terdeteksi

Pastikan player berjalan, putar lagu, lalu periksa Settings → Music. Setelah mengizinkan akses di System Settings → Privacy & Security → Automation, klik Retry detection. Aplikasi tidak membuka player atau memulai playback sendiri. Metadata saat notch tertutup diperbarui sekitar 15 detik; perubahan status playback diperiksa sekitar 2 detik.

## Memeriksa paket

File `.sha256` disediakan di samping ZIP. Dari folder yang berisi keduanya, jalankan:

```sh
shasum -a 256 -c Nubi-1.0.0-local.zip.sha256
```

Checksum memeriksa keutuhan unduhan/salinan, bukan identitas penerbit. Paket ini ditandatangani ad-hoc untuk penggunaan lokal, belum menggunakan Developer ID dan belum dinotarisasi Apple. Paket ini bukan rilis publik yang telah melewati Gatekeeper; jangan menonaktifkan perlindungan macOS untuk menjalankannya. Jika macOS menolak salinan yang diperoleh dari internet, bangun dari sumber lokal dengan `Scripts/build-local.sh` atau gunakan build Developer ID yang dinotarisasi.

## Menghapus

Nonaktifkan Launch at login, tutup aplikasi, lalu pindahkan salinan `Nubi.app` ke Trash. Preferensi lokal tetap tersimpan di domain `com.personal.notch`. Tidak ada server, akun Nubi, atau file pengguna yang diunggah oleh aplikasi.

Lihat `LIMITATIONS.md` untuk batasan fitur dan pengujian hardware yang masih diperlukan.
