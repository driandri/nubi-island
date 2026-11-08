# Nubi

Nubi adalah aplikasi native macOS yang menempatkan panel kecil di bagian atas layar. Panel ini merangkum musik, pengingat, jadwal, berkas, dan alat kerja tanpa membuka jendela besar. Nubi berjalan dari menu bar tanpa ikon Dock. Antarmukanya dibuat dengan SwiftUI dan AppKit; Terminal di dalam panel memakai SwiftTerm.

Nubi dapat dipakai di **macOS 14 atau lebih baru**. Sebagian fitur memerlukan izin macOS, akun layanan, atau versi sistem yang lebih baru. Izin diminta saat fiturnya digunakan, sesuai penjelasan di bawah.

## Mulai menggunakan

1. Pasang `Nubi.app` ke `~/Applications` atau `/Applications`, lalu buka dari lokasi tersebut. Panduan untuk paket ZIP dan pembaruan ada di [Docs/INSTALL.md](Docs/INSTALL.md).
2. Klik pill Nubi di bagian atas layar atau ikon Nubi di menu bar. Arahkan pointer ke pill untuk membuka panel sementara; klik pin di kepala panel agar tetap terbuka.
3. Buka **Settings** dari menu bar atau ikon roda gigi. Pilih kartu yang ingin tampil di **Home**, atur tab di **Navigasi**, dan pilih layar serta posisi panel di **Layar**.
4. Atur fitur yang ingin dipakai. Misalnya, pilih kota di **Settings → Home** untuk Cuaca dan Sholat, atau buka Calendar lalu tekan **Connect Calendar**. Deteksi musik otomatis dan pengingat sholat aktif secara bawaan; fitur yang memerlukan izin tambahan tetap mengikuti pilihan dan dialog macOS.

Tab bawah selalu menyediakan **Home** dan **Fitur**. Tab di antaranya dapat diatur dari Settings → Navigasi; Fitur membuka daftar seluruh panel. Saat tertutup, pill dapat menampilkan musik, timer, unduhan, dan pengingat yang sedang aktif. Klik kanan pill untuk perintah cepat; menu bar tetap tersedia saat panel tertutup.

## Fitur

### Musik dan waktu

- **Music.** Deteksi otomatis mengikuti Music, Spotify, atau tab video YouTube di Chrome yang sedang diputar. Panel menampilkan judul, artis, sampul, progres, volume, serta tombol sebelumnya, putar/jeda, dan berikutnya. Nubi tidak membuka player atau memulai lagu sendiri. Jika beberapa sumber aktif, sumber yang dipilih tetap dipakai sampai berhenti; tab YouTube yang sedang diputar dapat mengambil alih saat Chrome berada di depan. Mode manual dan Demo tersedia di Settings → Music.
- **Lirik.** Panel Music menampilkan cuplikan dan tampilan lirik yang dapat digulir. Nubi membaca lirik dari Music bila tersedia, lalu dapat mencari lirik yang belum ada melalui LRCLIB. Pencarian LRCLIB dapat dimatikan di Settings.
- **Timer.** Mode Standard menyediakan pilihan 1, 2, 3, 5, 10, atau 25 menit, serta durasi khusus 1–180 menit. Mode Pomodoro memakai 25 menit fokus, 5 menit istirahat, dan istirahat panjang 15 menit setelah empat sesi fokus. Tahap berikutnya dimulai saat Anda menekannya. Timer dapat dijeda, dilanjutkan, dan direset; sesi tidak bertahan setelah Nubi ditutup.
- **Live Activities.** Satu panel merangkum musik, timer, dan unduhan yang sedang berjalan. Pill tertutup juga dapat menampilkan beberapa aktivitas tersebut bersama-sama.

### Jadwal dan pengingat

- **Calendar.** Setelah **Connect Calendar**, Nubi menampilkan kalender bulanan, agenda hari terpilih, daftar acara mendatang, dan pratinjau acara berikutnya di Home. Tombol **Open Calendar** membuka aplikasi Calendar macOS. Nubi membaca acara melalui EventKit dan tidak membuat atau mengubahnya.
- **Sholat.** Gunakan kota yang dipilih di Settings → Home atau lokasi yang Anda izinkan. Panel menampilkan tanggal Masehi dan Hijriah, waktu sholat berikutnya, hitung mundur, lintasan matahari dari Terbit sampai Magrib, dan enam kartu waktu yang dapat dipilih. Perhitungan AlAdhan memakai metode Kemenag; jadwal masjid setempat dapat berbeda. Pengingat di island dapat diatur 5, 10, atau 30 menit sebelum waktu sholat dan bekerja selama Nubi berjalan.
- **Cuaca.** Masukkan kota atau pilih **Use current location** di Settings → Home. Prakiraan memakai Open-Meteo; Nubi meminta izin lokasi hanya ketika Anda memilih penggunaan lokasi saat ini.
- **Water.** Catat minum, tentukan target harian, ukuran sekali minum, dan interval, lalu lihat grafik hari ini. Pengingat perlu diaktifkan dan muncul antara 08.00–21.00 selama Nubi berjalan; pengingat berhenti ketika target tercapai. Catatan tujuh hari terakhir disimpan secara lokal.

### Catatan dan alat cepat

- **To-do dan Quick Notes.** To-do dapat ditambah, ditandai selesai, atau dihapus. Quick Notes menyimpan satu catatan teks. Keduanya tersimpan di Mac ini.
- **Launcher dan Calculator.** Launcher mencari aplikasi di folder Applications standar dan membuka aplikasi yang dipilih. Calculator mendukung hitung desimal, persen, perubahan tanda, hapus, dan masukan keyboard.
- **Quick Actions.** Cari perintah untuk membuka panel, mengambil tangkapan layar, atau menempatkan jendela ke zona layar. `⌘K` membuka daftar perintah saat panel aktif. Opsi **Window Snapping** di Settings → Integrasi memungkinkan jendela diseret ke zona di tepi atas; penempatan jendela memerlukan izin Accessibility.
- **Keep Awake.** Kartu Home ini mencegah layar tidur selama aktif, lalu melepas pencegahan ketika dimatikan atau Nubi ditutup.

### Berkas, perangkat, dan sistem

- **Shelf.** Seret hingga delapan file atau folder lokal ke Nubi, atau pilih lewat pemilih berkas. Klik nama untuk menemukannya di Finder, seret referensinya keluar, atau hapus dari daftar. Shelf hanya menyimpan referensi selama sesi; menghapus referensi tidak menghapus file asli.
- **Downloads.** Masukkan URL HTTPS dan pilih lokasi simpan untuk tiap unduhan. Panel menyediakan progres, batal, coba lagi, dan **Reveal in Finder**. Unduhan aktif dibatalkan saat Nubi ditutup. URL HTTP atau yang memuat kredensial ditolak.
- **Clipboard.** Riwayat bersifat opsional, memuat hingga 30 entri teks, tautan, atau warna, dan dapat dicari serta dipin. Secara bawaan riwayat hanya ada selama sesi; **Simpan riwayat di Mac ini** menyimpannya untuk peluncuran berikutnya. Aplikasi tertentu dapat dikecualikan. Tempel ke aplikasi depan memerlukan Accessibility; tanpa izin itu, entri dapat disalin lagi.
- **System, Battery, dan HUD.** Panel menampilkan informasi perangkat yang tersedia. Perubahan volume, mute, baterai, atau brightness dapat muncul sebentar di island bila perangkat mendukungnya. HUD macOS tetap tampil; brightness pada sebagian monitor eksternal memang tidak tersedia.
- **Sound Mixer.** Pilih perangkat input/output dan ubah volume sistem bila perangkat mendukung. Untuk volume per aplikasi, aktifkan **Mix apps** lalu tekan **Mulai**. Fitur ini memerlukan macOS 14.2 atau lebih baru dan izin System Audio Recording. Sesi routing tidak mulai otomatis saat Nubi dibuka, dan audio yang diproses tidak disimpan.
- **Camera & Mic dan tangkapan layar.** Panel menyediakan pratinjau kamera dan level mikrofon; tangkapan layar dapat ditambahkan ke Shelf. Izin kamera, mikrofon, atau Screen Recording diminta saat tindakan terkait dipilih. Pratinjau tidak menyimpan rekaman.
- **Notifications.** Jika diaktifkan dan Accessibility diizinkan, Nubi dapat menampilkan ulang banner yang terlihat dari aplikasi atau situs yang Anda pilih. Banner asli macOS tetap ada. Nubi tidak membaca riwayat Notification Center, tidak menyimpan isi pesan, dan tidak mengirim balasan.
- **Layar kunci.** Opsi di Settings → Layar dapat menampilkan pill, kartu musik, dan kontrol putar saat Mac terkunci. Fitur ini memakai API WindowServer privat, mati secara bawaan, dan mungkin berubah setelah pembaruan macOS.

### Developer

- **Proyek dan Git.** Tambahkan folder proyek secara eksplisit. Nubi membaca nama branch dan jumlah perubahan staged, belum staged, serta file baru, lalu dapat membuka folder di Finder atau editor pilihan. Nubi tidak mengubah repositori saat membaca status.
- **Terminal.** Tekan kontrol Terminal pada proyek terpilih untuk memulai shell lokal di folder itu. Sesi tetap ada saat panel ditutup sementara dan berakhir ketika Anda menutup sesi atau Nubi. Perintah berjalan sesuai yang Anda ketik.
- **Aktivitas agen.** Koneksi Claude Code, Codex CLI, dan Gemini CLI bersifat opsional. Setelah dihubungkan dan proses kepercayaan CLI disetujui, panel dapat menampilkan sesi dan tindakan terakhir. Catatan lokal berisi status, nama alat, dan paling jauh nama file; Nubi tidak menyimpan prompt atau keluaran alat. **Putuskan** menghapus perintah hook milik Nubi dari pengaturan penyedia.
- **Layanan GitHub dan Vercel.** Buka **Layanan** dari Developer untuk menghubungkan keduanya secara terpisah. GitHub memakai remote `origin` dan branch dari proyek terpilih untuk membaca pull request serta Actions. Vercel memakai `.vercel/project.json` untuk membaca deployment. Token disimpan di Keychain macOS dan dihapus per layanan melalui **Putuskan**. Tidak ada akun yang terhubung secara bawaan; permintaan jaringan hanya dibuat saat panel dibuka, proyek berubah, atau Anda menekan **Perbarui**.

## Izin dan data

| Izin atau koneksi | Kapan diperlukan | Penggunaan |
| --- | --- | --- |
| Automation | Saat mengakses player yang berjalan | Membaca status dan mengirim perintah Music/Spotify/Chrome. Untuk YouTube di Chrome, aktifkan **View → Developer → Allow JavaScript from Apple Events**. |
| Calendar penuh | Saat menekan **Connect Calendar** | Membaca agenda melalui EventKit. Dapat dicabut di System Settings → Privacy & Security → Calendars. |
| Location | Saat memilih **Use current location** | Menentukan kota untuk Cuaca dan Sholat. Memasukkan kota manual tidak memerlukan izin ini. |
| Accessibility | Saat memakai tempel, mirror banner, atau Window Snapping | Mengakses elemen sistem yang diperlukan oleh fitur tersebut. |
| System Audio Recording | Saat memulai Mixer per aplikasi | Merutekan audio selama sesi Mixer. |
| Screen Recording, Camera, Microphone | Saat memilih tindakan terkait | Tangkapan layar atau pratinjau perangkat. |
| Login Items | Saat mengaktifkan **Launch at login** | Membuka Nubi saat masuk ke macOS. |

Preferensi disimpan di UserDefaults dengan identitas `com.personal.notch`. To-do, Quick Notes, dan riwayat Clipboard yang Anda pilih untuk disimpan berada di penyimpanan lokal; token GitHub/Vercel berada di Keychain. Nubi tidak memiliki backend atau telemetri sendiri. Fitur tertentu menghubungi layanan langsung: Open-Meteo untuk cuaca, AlAdhan untuk jadwal sholat, LRCLIB untuk lirik opsional, GitHub/Vercel jika dihubungkan, dan URL unduhan yang Anda masukkan. Sampul Spotify dapat dimuat dari CDN gambar Spotify.

## Jika fitur belum bekerja

- **Musik tidak terdeteksi:** putar lagu di aplikasi yang didukung, periksa izin di System Settings → Privacy & Security → Automation, lalu tekan **Retry detection** di Settings → Music. Untuk YouTube, periksa juga pengaturan JavaScript from Apple Events di Chrome.
- **Calendar kosong:** tekan **Connect Calendar** dan periksa izin Calendar untuk Nubi. Agenda hanya tampil setelah akses penuh diberikan.
- **Cuaca atau Sholat kosong:** tentukan kota di Settings → Home atau gunakan lokasi saat ini, lalu perbarui. Jadwal Sholat memakai kota yang sama dengan Cuaca.
- **Mixer tidak merutekan audio:** periksa izin System Audio Recording dan perangkat output, lalu tekan **Mulai** lagi. Perangkat atau format audio yang tidak didukung dapat membuat Nubi menghentikan routing.

## Build dan pengujian

Untuk mengembangkan aplikasi, buka `Notch.xcodeproj`, pilih skema **Notch** dan target **My Mac**, lalu jalankan. Skrip berikut membuat build Release lokal bertanda tangan ad-hoc secara bawaan dan memverifikasi bundle:

```sh
./Scripts/build-local.sh
open build/Build/Products/Release/Nubi.app
```

Jika memiliki identitas Apple Development, set `NUBI_SIGN_IDENTITY` ke hash identitas saat menjalankan skrip. Gunakan satu lokasi pemasangan tetap agar izin macOS lebih stabil. Build Apple Development maupun ad-hoc ditujukan untuk penggunaan lokal; paket ini belum ditandatangani dengan Developer ID atau dinotarisasi untuk distribusi publik.

Terminal memakai build plug-in SwiftTerm. Xcode mungkin meminta peninjauan plug-in sebelum build CLI. Setelah meninjau sumbernya, `NUBI_SKIP_PACKAGE_PLUGIN_VALIDATION=1` dapat dipakai untuk build tanpa dialog validasi. Untuk membuat ZIP lokal beserta checksum dan petunjuk pemasangan, jalankan `./Scripts/package-local.sh`.

```sh
swift test
```

Tes Swift Package memeriksa logika model dan tidak menggantikan pengujian aplikasi serta izin macOS. Lihat [catatan validasi](Docs/VALIDATION.md) untuk hasil yang sudah diuji dan [batasan serta rencana](Docs/ROADMAP.md) untuk pekerjaan yang masih tersisa. Detail pemasangan dan pembaruan ada di [Docs/INSTALL.md](Docs/INSTALL.md); struktur kode ada di [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md).
