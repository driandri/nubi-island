import AppKit
import ServiceManagement
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var music: MusicModel
    @ObservedObject var calendar: CalendarModel
    @ObservedObject var clipboard: ClipboardHistoryModel
    @ObservedObject var notifications: NotificationBannerModel
    @ObservedObject var mixer: SoundMixerModel
    let openSettings: () -> Void
    let finish: () -> Void

    @State private var page = 0
    @State private var loginMessage: String?
    private let white = Color.white
    private let background = LinearGradient(
        colors: [Color(red: 0.27, green: 0.04, blue: 0.66), Color(red: 0.41, green: 0.31, blue: 0.92),
                 Color(red: 0.78, green: 0.36, blue: 0.62), Color(red: 0.99, green: 0.50, blue: 0.27)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            if page < 3 { introduction }
            else { quickSetup }
        }
        .frame(width: 760, height: 520)
        .preferredColorScheme(.dark)
    }

    private var introduction: some View {
        VStack(spacing: 0) {
            HStack {
                Text("NUBI").tracking(3).font(.system(size: 11, weight: .heavy))
                Spacer()
                Button("Lewati") { finish() }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            }.padding(.leading, 96).padding(.trailing, 28).padding(.top, 38)
            Spacer(minLength: 10)
            illustration
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                Text(introTitle).font(.system(size: 23, weight: .bold)).multilineTextAlignment(.center)
                Text(introSubtitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.83))
                    .multilineTextAlignment(.center).frame(maxWidth: 560)
            }.padding(.horizontal, 35)
            HStack {
                Button("Kembali") { page = max(0, page - 1) }
                    .opacity(page == 0 ? 0 : 1).disabled(page == 0)
                Spacer()
                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule().fill(index == page ? .white : .white.opacity(0.32))
                            .frame(width: index == page ? 15 : 5, height: 5)
                    }
                }
                Spacer()
                Button(page == 2 ? "Atur akses" : "Lanjut") { page += 1 }
                    .buttonStyle(.borderedProminent).tint(.white.opacity(0.25))
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 28).padding(.top, 25).padding(.bottom, 25)
        }
        .foregroundStyle(white)
    }

    private var introTitle: String {
        switch page {
        case 0: "Jadikan notch pusat aktivitas harian"
        case 1: "Musik, timer, dan alat kerja dalam satu tempat"
        default: "Pilih akses yang memang ingin dipakai"
        }
    }
    private var introSubtitle: String {
        switch page {
        case 0: "Buka panel dari bagian atas layar untuk melihat hal penting tanpa berpindah aplikasi."
        case 1: "Atur Home, kontrol musik dan suara, mulai fokus, serta buka alat cepat saat dibutuhkan."
        default: "Nubi meminta izin hanya ketika Anda mengaktifkan fitur terkait. Semua pilihan bisa diubah nanti di Settings."
        }
    }

    private var illustration: some View {
        ZStack {
            Circle().fill(.white.opacity(0.10)).frame(width: 310, height: 310).blur(radius: 18)
            RoundedRectangle(cornerRadius: 22).fill(.black.opacity(0.15))
                .frame(width: 324, height: 205).offset(y: 14).blur(radius: 12)
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.92)).frame(width: 310, height: 190)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.cyan.opacity(0.65), lineWidth: 5))
                    Capsule().fill(.black).frame(width: 78, height: 14)
                    Image(systemName: page == 0 ? "cursorarrow.click.2" : page == 1 ? "waveform" : "checkmark.shield.fill")
                        .font(.system(size: 76, weight: .semibold))
                        .foregroundStyle(page == 0 ? .indigo : page == 1 ? .pink : .purple)
                        .shadow(color: .purple.opacity(0.3), radius: 9, y: 7)
                        .offset(y: 46)
                }
                RoundedRectangle(cornerRadius: 11).fill(.cyan.opacity(0.72)).frame(width: 360, height: 19)
                    .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.6)).frame(width: 65, height: 5) }
            }
            floating("calendar", x: -280, y: -105, color: .cyan)
            floating("music.note", x: 275, y: -100, color: .cyan)
            floating("timer", x: 280, y: 75, color: .orange)
            floating("tray.full.fill", x: -270, y: 80, color: .blue)
            floating("checklist", x: -180, y: -155, color: .pink)
            floating("sun.max.fill", x: 185, y: -170, color: .yellow)
        }
        .frame(maxWidth: .infinity, minHeight: 295)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ilustrasi Mac dengan fitur Nubi")
    }

    private func floating(_ symbol: String, x: CGFloat, y: CGFloat, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 33, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 56, height: 56)
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.23), radius: 8, y: 7)
            .rotationEffect(.degrees(Double(x / 34)))
            .offset(x: x, y: y)
    }

    private var quickSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { page = 2 } label: { Label("Kembali", systemImage: "chevron.left") }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("NUBI · QUICK SETUP").font(.system(size: 10, weight: .bold)).tracking(1.6)
            }.foregroundStyle(.white.opacity(0.8))
            Text("Atur yang Anda perlukan")
                .font(.system(size: 26, weight: .bold)).frame(maxWidth: .infinity, alignment: .center)
            Text("Fitur tanpa akses tambahan langsung siap. Anda bisa melewati langkah lain dan mengaturnya nanti.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.77))
                .frame(maxWidth: .infinity, alignment: .center)
            ScrollView {
                VStack(spacing: 6) {
                    setupRow("power", title: "Buka saat login", detail: "Jalankan Nubi ketika Mac dinyalakan",
                             status: loginMessage ?? (SMAppService.mainApp.status == .enabled ? "Aktif" : nil),
                             button: SMAppService.mainApp.status == .enabled ? "Aktif" : "Aktifkan") { enableLogin() }
                    setupRow("music.note", title: "Apple Music & Spotify", detail: "Tampilkan musik yang sedang diputar; izinkan Automation jika diminta",
                             status: music.permissionMessage ?? music.message, button: "Hubungkan") { music.connect() }
                    setupRow("play.rectangle.fill", title: "YouTube di Chrome", detail: "Aktifkan JavaScript dari Apple Events pada menu Developer Chrome",
                             status: music.browserMessage == nil ? nil : "Periksa Chrome dan izin Automation di Settings → Music",
                             button: "Coba lagi") { music.connect() }
                    setupRow("calendar", title: "Kalender", detail: "Baca acara mendatang untuk Home dan panel Calendar",
                             status: calendar.statusText,
                             button: calendar.access == .fullAccess ? "Terhubung" : calendar.access == .denied || calendar.access == .restricted ? "Buka Settings" : "Hubungkan") {
                        if calendar.access == .denied || calendar.access == .restricted { calendar.openAccessSettings() }
                        else { calendar.requestAccess() }
                    }
                    setupRow("doc.on.clipboard", title: "Riwayat clipboard", detail: "Simpan tiga salinan terakhir hanya selama Nubi berjalan",
                             status: clipboard.enabled ? "Aktif" : nil, button: clipboard.enabled ? "Aktif" : "Aktifkan") { clipboard.enabled = true }
                    setupRow("slider.horizontal.3", title: "Sound Mixer", detail: "Volume per aplikasi membutuhkan izin System Audio Recording",
                             status: mixer.enabled ? mixer.status : nil, button: mixer.sessionActive ? "Aktif" : "Mulai") {
                        if mixer.enabled { mixer.retry() } else { mixer.setEnabled(true) }
                    }
                    setupRow("bell.badge", title: "Banner notifikasi", detail: "Pilih aplikasi dan beri izin Accessibility melalui Settings",
                             status: notifications.enabled ? notifications.status : nil, button: "Atur") { openSettings() }
                }
            }
            HStack {
                Text("Izin yang dilewati dapat diatur di Settings.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.73))
                Spacer()
                Button("Mulai pakai Nubi") { finish() }
                    .buttonStyle(.borderedProminent).tint(.white.opacity(0.25))
            }.padding(.top, 5)
        }
        .padding(.horizontal, 25).padding(.top, 45).padding(.bottom, 22)
        .foregroundStyle(.white)
    }

    private func setupRow(_ symbol: String, title: String, detail: String, status: String?,
                          button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(width: 27)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .bold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                if let status { Text(status).font(.system(size: 9)).foregroundStyle(.white.opacity(0.85)).lineLimit(1) }
            }
            Spacer(minLength: 5)
            Button(button, action: action)
                .buttonStyle(.borderedProminent).tint(.white.opacity(0.22))
                .font(.system(size: 10, weight: .semibold))
                .disabled(button == "Aktif" || button == "Terhubung")
        }
        .padding(.horizontal, 13).frame(minHeight: 48)
        .background(.black.opacity(0.21), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.09)))
    }

    private func enableLogin() {
        do {
            try SMAppService.mainApp.register()
            loginMessage = SMAppService.mainApp.status == .requiresApproval
                ? "Setujui di System Settings → Login Items" : "Aktif"
        } catch { loginMessage = error.localizedDescription }
    }
}
