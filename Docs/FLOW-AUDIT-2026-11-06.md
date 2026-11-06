# Audit flow Nubi — 6 November 2026

Audit ini membedakan pemeriksaan kode dan tes dari interaksi aplikasi native. Build yang diperiksa berasal dari `Scripts/build-local.sh`, bukan salinan lama di `~/Applications`.

| Flow | Bukti saat ini | Status |
| --- | --- | --- |
| Pill, Home, navigasi, Peek, pin, collapse | Home dan perpindahan ke Calendar/Music/Mixer terlihat pada accessibility tree; tes state dan geometri lulus. Penjaga pointer ditambahkan untuk perubahan ukuran panel. | Perlu uji pointer manual setelah perpindahan antar-panel yang tingginya berbeda. |
| Calendar | Grid bulan, pilihan tanggal, agenda harian, upcoming, dan tombol Join terlihat saat akses EventKit tersedia. Tes mencakup lintas bulan, acara yang melewati tengah malam, lebih dari 64 acara, dan pencabutan akses. | Berfungsi pada sesi yang diizinkan; izin pada build ad-hoc terbaru belum tersedia kembali. |
| Music dan Live Activities | YouTube terdeteksi otomatis di panel Music; kontrol dan rute Live Activities ada. Tes media dan arbitrasi aktivitas lulus. | Perintah putar/jeda Spotify dan YouTube belum dicoba langsung pada build ini. |
| Timer, Launcher, To-do, Calculator | Transisi Pomodoro, pencarian aplikasi, penyimpanan tugas, dan operasi kalkulator lulus tes. | Kontrol native tiap rute belum diklik ulang pada build ini. |
| Downloads, Clipboard, Shelf, Quick Actions, capture | Tes URL HTTPS, batal/selesai unduhan, riwayat Clipboard, dan ZIP/OCR Shelf yang ada tetap lulus. | Dialog simpan, paste ke aplikasi lain, shortcut, screenshot picker, kamera, dan mikrofon belum diuji langsung. |
| Prayer, Water, Notes, Keep Awake, Battery, System | Tes jadwal Sholat, Water, Quick Notes, serta preferensi yang ada lulus. Perangkat uji Mac mini tidak memberi baterai internal. | Pengingat nyata dan perangkat baterai perlu perangkat yang sesuai. |
| Mixer dan HUD | Mixer menampilkan output, input, gain, dan tombol meter mikrofon. Settings menampilkan pilihan HUD dan status mute mikrofon. Tes prioritas alert lulus. | Brightness pada layar terpilih tidak tersedia; perubahan brightness, mute fisik, pengisian baterai, dan izin mikrofon belum diuji langsung. |
| Banyak layar dan fullscreen | Tiga layar terdeteksi; Settings sedang dalam mode All displays. Tes zona hover dan aturan visibilitas lulus. | Hover/keluar fullscreen serta posisi ketiga panel belum terkonfirmasi langsung. |

## Temuan dan tindak lanjut

1. **Panel dapat menutup setelah klik kartu Home ketika tinggi panel berubah.** Jalur reproduksi: buka Home, klik Calendar atau Music, lalu biarkan pointer pada koordinat lama. Penjaga posisi pointer dan jeda navigasi ditambahkan; uji UI otomatis masih memindahkan pointer sehingga tidak dapat memisahkan gerakan nyata dari perubahan frame. Perlu uji mouse manual.
2. **Izin Calendar pada bundle build ad-hoc perlu dicek lagi setelah rebuild.** Calendar sempat menampilkan agenda nyata pada satu proses, tetapi proses build terbaru kembali menampilkan Connect Calendar. Penyebab TCC/signature belum dipastikan; jangan menganggap izin akan stabil sampai diuji pada salinan terpasang dengan identitas tanda tangan yang tetap.
3. **Data brightness tidak tersedia pada layar yang sedang dipilih.** Settings menyatakan ini dengan jelas; HUD hanya muncul pada layar yang memberi nilai melalui IOKit.

Tidak ada kegagalan tes otomatis atau kegagalan build yang tersisa. Hasil tes tidak menggantikan uji izin dan perangkat nyata di atas.
