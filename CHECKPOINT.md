# Session Checkpoint: FSR Analyzer — 2D Map-View Horizon Auto-Tracking & Lateral Fault Kinematics (2026-10-19)

## 1. Objective & Starting Context
- **Target Eksperimen**:
  - `/run/media/sandbox-main/BIG DATA 6TB/01_EXP_SANDBOX_MASTER/05_NEW_RUNS_2026/new_exp_OM_TERR/THRUST_Fault EXP 2026 new/Thin Skin/2 cm/` (EXP 0, 1, 2, 3).
- **Initial Goal**:
  1. Mengalihkan alur observasi dari penampang kymograf 1D ke **2D Map View (Tampak Atas)** pada bidang regangan proksi Shortening Rate (SR: $e_{xx}$) dan Spatial Velocity Magnitude Gradient (VG: $|\nabla V|$).
  2. Membangun alat bantu interpretasi digital interaktif bergaya *seismic horizon interpretation auto-tracking* untuk menandai momen dan geometri sesar (*Fault Surface Rupture* / FSR).
  3. Memungkinkan pemilihan sesar bertahap (*multi-fault management*), pelacakan mundur (*backward & forward tracking*), deteksi tepi terluar strike sesar, serta penentuan timing nukleasi (*onset*) hingga tembus sempurna (*full breach*).
  4. Menggambar kurva **Along-Strike $Y$ versus Cumulative Strain $\varepsilon$ (Plot A)** untuk menghitung kecepatan propagasi lateral sesar ($V_{\text{lat}}$ dalam cm/min dan mm/s) serta regangan pembentukan sesar ($\Delta\varepsilon_{\text{rupture}}$).
  5. Mengintegrasikan citra foto asli (top-down DSLR nadir) sebagai *visual reference overlay* dengan slider transparansi (*opacity blending*).
  6. Mengotomatiskan pelacakan 2-titik (*2-Point Auto-Tracking*) dengan **deteksi puncak fisik sub-pixel kuadratik** di antara frame awal dan final.

---

## 2. Completed Work & Artifacts

### A. Aplikasi Interaktif & Server
- `/home/sandbox-main/1. RE_XnMP/FSR_Analyzer.html` (dan alias `fsr_seismic_autotracker.html` / `fsr_analyzer.html`):
  - Aplikasi web mandiri (*standalone HTML5 Canvas*) dengan akselerasi rendering, kontrol multikanvas, dan zoom/pan interaktif.
  - Dua tombol khusus di toolbar: `[⭐ Deteksi Awal]` (Hotkey `A`) dan `[🏁 Deteksi Final]` (Hotkey `F`).
  - Algoritma `detectPeaksBetweenOnsetAndBreach`: melakukan *sub-pixel quadratic peak detection* (`snapXColAtRow`) pada frame perantara $t \in [t_{onset}, t_{breach}]$ di sepanjang koridor sesar dengan ambang batas fisika $T \ge 0.020$.
  - Panel **Plot A (Along-Strike $Y$ vs Cumulative Strain $\varepsilon$)** yang menampilkan amplop propagasi lateral riil $[Y_{\min}(t), Y_{\max}(t)]$.
  - **Flip Vertikal VG & SR (Up/Down)**: Heatmap SR & VG dibalik vertikal (`dispRow = r`, `flipVertical: true`, Hotkey `V`), selaras persis dengan rekahan pasir pada foto.
  - **Aspect Ratio Fisik 1:1 Terkunci**: Dimensi kanvas View M mengikuti rasio fisik sandbox $\Delta X / \Delta Y = 450.0 / 347.0 \approx 1.29683$ (panjang $X$ fixed, lebar $Y$ proporsional), sehingga grid pasir $2 \times 2\text{ cm}$ tampil bujur sangkar sempurna.
  - **Zoom Kanvas Dikunci (`zoomLocked: true`)**: Wheel zoom dinonaktifkan permanen (`zoom = 1.0`, `panX = 0`, `panY = 0`) agar tampilan kanvas tidak sengaja melar atau tergeser.
  - **Dual-Layer Photo Blend**: Slider transparansi foto latar belakang ($0\% - 100\%$, Hotkeys `[` dan `]`, toggle `P`) dengan *strain-weighted blending*.
  - **Dual Editing Engine**: Alat toolbar `[✂️ Hapus Titik]` (Hotkey `5`/`X`) dan modul sidebar `Koreksi & Pangkas Titik` untuk menghapus titik interpolasi asing yang melompat.
  - Ekspor/impor katalog interpretasi ke format JSON (`FSR_Interpreted_Picks_EXP_*.json`) dan tabel metrik kinematika CSV (`FSR_Kinematics_EXP_*.csv`).
- `/home/sandbox-main/1. RE_XnMP/launch_fsr_analyzer.py` (dan `launch_fsr_tracker.py`):
  - Local HTTP daemon di `http://localhost:8089/FSR_Analyzer.html` dengan endpoint REST API `/api/save_picks` untuk menyimpan hasil picking langsung ke disk.
- `/home/sandbox-main/1. RE_XnMP/assets/resized_photos/`:
  - 1.551 foto eksperimen terpotong presisi dan di-resize ke $960 \times 743\text{ px}$ (JPEG Q78, ~50–100 KB/frame):
    - `EXP_3`: 312 frame (31 MB)
    - `EXP_2`: 316 frame (30 MB)
    - `EXP_1`: 397 frame (35 MB)
    - `EXP_0`: 526 frame (46 MB)
- `/home/sandbox-main/1. RE_XnMP/fsr_autotracker_data.js`:
  - Basis data ringkas volume 3D $H \times W \times T$ untuk EXP 0, 1, 2, dan 3.

### B. Repositori GitHub & Otentikasi SSH
- **Otentikasi SSH GitHub**:
  - Kunci SSH `FD ITB` (`~/.ssh/id_ed25519`, fingerprint `SHA256:VrioobpEkGlkjaODJByxGyZrO+PDlCerITrAtjAKG34`) terotentikasi penuh dengan GitHub.
- **Repositori `PIV-kymograph-fault-detection`** (`git@github.com:terryfurqan/PIV-kymograph-fault-detection.git`):
  - Berhasil di-push ke branch `main` (`f08669a`).
- **Repositori `00. AGY Skills`** (`git@github.com:terryfurqan/agy-skills.git`):
  - Berhasil di-push ke branch `main` (`50dc3da`).

---

## 3. Decision Log & Idea Evolution

| Decision / Topic | Initial / Explored Idea | Pivot / Why Discarded | Settled Decision & Rationale |
| :--- | :--- | :--- | :--- |
| **Domain Pengamatan FSR** | Menginterpretasi dan mengklik picking pada diagram kymograf 1D spasiotemporal ($X \times t$). | User mengoreksi: sesar analog diamati dari **Map View 2D (tampak atas)**, karena kymograf 1D mengaburkan orientasi strike oblique dan propagasi lateral segmen. | **Map View Interaktif 2D** pada medan SR ($e_{xx}$) dan VG ($|\nabla V|$) sebagai kanvas utama interpretasi. |
| **Katalog Sesar Bawaan** | Otomatis memuat katalog sesar statis awal hasil deteksi kymograf lama. | User meminta kanvas bersih agar penafsiran geologis dapat dilakukan murni secara manual tanpa bias deteksi algoritma awal. | **Katalog Bersih (Zero-Seed Initial State)**: Pengguna bebas menambah sesar baru (`F1`, `F2`, dst.) dan menentukan waktu inisiasi sendiri. |
| **Pelacakan Propagasi Sesar** | Menginterpolasi garis secara linear sintetis (*geometric resize/stretching* antara awal dan akhir). | Menghasilkan garis artifisial yang tidak merepresentasikan fisika lokalisasi geser pasir dan akselerasi/deselerasi lateral di dinding batas. | **Pencarian Puncak Fisik Sub-Pixel (`detectPeaksBetweenOnsetAndBreach`)**: Setiap frame perantara dipindai secara independen untuk menemukan igir deformasi maksimum $\ge T = 0.020$ di dalam koridor strike. |
| **Ergonomi Deteksi Awal & Final** | Melakukan auto-tracking manual satu per satu pada puluhan frame secara berulang. | Melelahkan dan memakan waktu interpretasi. | **2-Point Guided Peak Auto-Tracker**: Cukup 1 klik `[⭐ Deteksi Awal]` (Hotkey `A`) pada inisiasi dan 1 klik `[🏁 Deteksi Final]` (Hotkey `F`) pada saat sesar matang; seluruh frame di antaranya langsung terlacak otomatis. |
| **Referensi Visual Geologis** | Menampilkan kontur warna strain rate secara terisolasi tanpa citra foto asli. | Sulit mengorelasikan diskontinuitas numerik strain rate dengan jejak rekahan morfologis fisik pada pasir (*scarp*, *bulge*, *shear band*). | **Dual-Layer Map View Overlay**: Mengintegrasikan citra foto asli nadir top-down dengan slider transparansi (*opacity blending*) dan tombol sakelar cepat (*Spacebar*). |
| **Penyimpanan Berkas Aplikasi** | Nama awal: `fsr_seismic_autotracker.html`. | User meminta standardisasi penamaan resmi menjadi **FSR Analyzer**. | Disimpan resmi sebagai **`FSR_Analyzer.html`** (dengan skrip peluncur `launch_fsr_analyzer.py`), dan disinkronkan ke repositori GitHub master. |
| **Koreksi & Penghapusan Titik Interpolasi** | Interpolasi otomatis 2-titik tidak dapat diedit titik perantara-nya jika terjadi kesalahan penangkapan igir atau melompat ke sesar lain. | User menemukan kasus di mana algoritma puncak melompat ke cabang sesar asing di ujung bawah ($Y \le 200\text{ mm}$), dan meminta modul/tombol untuk menghapus titik interpolasi tersebut. | **Dual Editing Engine (Interactive Eraser + Sidebar Module)**: 1) Alat toolbar `[✂️ Hapus Titik]` (`5`/`X`/`E`) dengan hover reticle merah dan drag-to-erase brush; 2) Modul sidebar `Koreksi & Pangkas Titik` (`Potong Bawah`, `Potong Atas`, `Pangkas Lompatan (|ΔX|>15)`, `Hapus Semua`, `Reset Puncak`, `Bekukan Jadi Keyframe`); 3) Perbaikan internal algoritma `detectPeaksBetweenOnsetAndBreach` dengan pembatasan window baris $Y$ dan filter kontinuitas spatial cluster. |
| **Orientasi Tampilan Horizontal (Dorongan Kiri ke Kanan)** | Orientasi baku kanvas menampilkan dinding pendorong di sisi kanan bergerak ke kiri (menuju $X=0\text{ mm}$ di kiri). | User meminta membalik orientasi tampilan: "sekarang di flip tampilannya dinding pendorong selalu bergerak dari kiri ke kanan" agar konsisten dengan standar presentasi tektonik/geologi analog. | **Bijective Visual Flip Engine (`flipHorizontal: true`)**: 1) Kanvas Map View 2D dibalik horizontal dengan pusher $X \approx 450\text{ mm}$ di KIRI dan bergerak ke KANAN menuju cekungan foreland ($X=0\text{ mm}$); 2) Transformasi `mapWorldToScreen` dan `screenToMapWorld` dibalik secara matematis sehingga picking, snapping, erasing, dan hover akurat 100%; 3) Kymograf referensi Centerline (Plot B) ikut dicerminkan secara horizontal agar sumbu $X$ sinkron sempurna; 4) Garis pendorong putus-putus putih bergerak dari kiri ke kanan; 5) Tombol sakelar `[🔁 Dorongan: Kiri ➔ Kanan]` (Hotkey `H`) terpasang di toolbar untuk fleksibilitas orientasi. |
| **Foto Latar Belakang Eksperimen Ringan (Lightweight Resized Background Photo)** | Tampilan Map View hanya menampilkan kontur strain rate SR/VG sintetis tanpa tekstur fisik pasir. | User meminta: "tampilkan background foto berupa foto eksperimen yg telah di resize .. jagi ga terlalu berat" agar rekahan morfologis pasir (*scarp*, *bulge*, *shear band*) terlihat jelas namun tetap sangat ringan dan lancar saat scrubbing. | **Dual-Layer Dynamic Blend Engine**: 1) Seluruh foto eksperimen (EXP 3, 2, 1, 0) dipotong presisi ke area fisik aktif ($X: 0..450\text{ mm}, Y: 30.6..377.6\text{ mm}$) dan di-resize ke resolusi ringan $960 \times 743\text{ px}$ (JPEG Q78, rata-rata hanya ~45–100 KB per frame); 2) Dilengkapi *in-memory image cache* dan *prefetcher agresif* (+5 frame ke depan, -3 frame ke belakang) sehingga scrubbing nol-latensi (0.7 ms fetch); 3) *Strain-weighted alpha blending*: area regangan rendah/stabil dibuat transparan sehingga tekstur butiran pasir dan grid tampak kristal tajam, sementara pita regangan sesar menyala terang di atas pasir; 4) Tombol sakelar toolbar `[📷 Foto: ON/OFF]` (Hotkey `P`) dan slider `Blend: 0% .. 100%` (Hotkeys `[` dan `]`). |
| **Flip Vertikal Heatmap VG & SR (Up/Down)** | Orientasi vertikal baris heatmap VG/SR terbalik atas-bawah terhadap foto rekahan fisik pasir. | User meminta: "VG dan SR nya di flip up/down". Heatmap sebelumnya menggunakan `dispRow = (exp.map_h - 1) - r` yang membalik baris atas ke bawah, terbalik dibanding rekahan foto asli. | **Vertical Flip Engine (`flipVertical: true`)**: 1) `dispRow = r` menempatkan baris atas foto dan array tepat di atas kanvas (`dispRow = 0`); 2) Koordinat proyeksi `mapWorldToScreen` dan inversinya `screenToMapWorld` disinkronkan sehingga klik, snapping, erasing, reticle, dan polylines sesar tepat menempel di atas rekahan foto; 3) Tombol sakelar toolbar `[⇅ VG/SR: Flip Up/Down]` (Hotkey `V`). |
| **View M Sesuai True Physical Aspect Ratio & Kunci Zoom** | Kotak kanvas Map View 2D meregang vertikal memenuhi sisa viewport, mendistorsi grid bujur sangkar pasir $2 \times 2\text{ cm}$ menjadi persegi panjang lonjong. Interaksi mouse wheel juga membuat kanvas ter-zoom in/out tidak sengaja. | User meminta: "view M /2d map view nya dibikin seuai aspect ratio nya ... fixed panjang nya ... lebarnya menyeseuaikan ..dan dikunci saja zoom nya..". | **True Aspect Ratio & Locked Zoom (`zoomLocked: true`)**: 1) Dimensi plot View M dihitung strictly dari rasio fisik riil sandbox $\Delta X / \Delta Y = 450.0\text{ mm} / 347.0\text{ mm} \approx 1.29683$ (panjang $X$ fixed, lebar $Y$ proporsional); 2) Grid bujur sangkar pasir $2 \times 2\text{ cm}$ tampil bujur sangkar sempurna tanpa distorsi regangan; 3) Interaksi mouse wheel zoom dinonaktifkan permanen (`zoom = 1.0`, `panX = 0`, `panY = 0`) dan indikator status `[🔒 Zoom: Dikunci]` dipasang di toolbar. |

---

## 4. Current Status
- **Working / Verified**:
  - Aplikasi web `FSR_Analyzer.html` aktif di `http://localhost:8089/FSR_Analyzer.html` (tersinkronkan ke `fsr_analyzer.html` dan `fsr_seismic_autotracker.html`).
  - **Flip Vertikal VG & SR (Up/Down)** aktif default (`flipVertical: true`), pita inferno/plasma menempel persis di atas rekahan fisik pasir.
  - **Aspect Ratio Fisik 1:1 Terkunci**: Grid pasir tampak bujur sangkar murni ($450\text{ mm} : 347\text{ mm}$).
  - **Zoom Kanvas Terkunci**: Wheel zoom dan drag pan dinonaktifkan (`zoom = 1.0`, `panX = 0`, `panY = 0`), kanvas stabil 100%.
  - **Foto Latar Belakang Eksperimen Ringan** aktif di `assets/resized_photos/` untuk EXP 0, 1, 2, 3.
  - **GitHub Remote Sync via SSH**: Seluruh commit telah di-push sukses ke `git@github.com:terryfurqan/PIV-kymograph-fault-detection.git` dan `git@github.com:terryfurqan/agy-skills.git` menggunakan SSH key `FD ITB`.
- **In-Progress / Pending**:
  - Batching interpretasi manual untuk 4 eksperimen Thin Skin 2 cm (EXP 0, EXP 1, EXP 2, EXP 3) menggunakan fitur 2-Point Auto-Tracking (`Deteksi Awal` & `Deteksi Final`).
  - Kompilasi matriks komparatif kinematika propagasi lateral ($V_{\text{lat}}, \varepsilon_{\text{init}}, \varepsilon_{\text{full}}, \Delta\varepsilon_{\text{rupture}}$) lintas eksperimen.
  - Penyiapan kompilasi visualisasi Plot A untuk bahan laporan/publikasi.
- **Known Blockers / Caveats**:
  - Tidak ada kendala teknis atau otentikasi. Semua dependensi data dan server lokal siap pakai.

---

## 5. Next Session Scope & Action Plan
1. **Eksekusi Penafsiran Sesar Interaktif (Picking)**:
   - Membuka `http://localhost:8089/FSR_Analyzer.html` untuk Thin Skin 2 cm (EXP 0, 1, 2, 3).
   - Menandai inisiasi (`[⭐ Deteksi Awal]`, Hotkey `A`) dan tembus sempurna (`[🏁 Deteksi Final]`, Hotkey `F`) untuk sesar-sesar utama (F1 s.d. F5).
   - Melakukan koreksi titik / trimming jika terdapat lonjakan interpolasi menggunakan tool `[✂️ Hapus Titik]` (`5`/`X`) atau sidebar module.
2. **Kompilasi Matriks Kinematika Komparatif**:
   - Menyimpan hasil picking via tombol `💾 Simpan JSON` (tersimpan ke `FSR_Interpreted_Picks_EXP_*.json`).
   - Mengompilasi tabel metrik lateral kinematics ($V_{\text{lat}}$, $\varepsilon_{\text{init}}$, $\varepsilon_{\text{full}}$, $\Delta\varepsilon_{\text{rupture}}$) lintas EXP 0, 1, 2, dan 3.
3. **Penyelarasan Publikasi & Pelaporan**:
   - Mengintegrasikan Plot A ($Y \text{ vs } \varepsilon$) ke dalam slide PowerPoint (`sbx-slice-ppt` / `laporan-sbx-single`) atau manuskrip publikasi.
4. **Git Sync**:
   - Melakukan `git commit` dan `git push origin main` via SSH untuk menyimpan hasil picking JSON dan CSV ke GitHub.

---

## 6. Suggested Skills & Tools for Next Session
- `visualisasi-data`: Merancang figur publikasi komparatif multi-panel untuk kurva $Y \text{ vs } \varepsilon$ lintas model.
- `laporan-sbx-single`: Mengompilasi evolusi FSR ke dalam format presentasi PowerPoint 16:9.
- `grain-suite`: Menjalankan tahapan PIV atau ekspor kontainer `.grainraw` jika ada eksperimen baru yang ingin dimasukkan ke FSR Analyzer.
