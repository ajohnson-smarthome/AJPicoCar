import SwiftUI

struct FirmwareView: View {
    let palette: Palette
    @ObservedObject var status: CarStatus
    @StateObject private var client = UpdateClient()

    @State private var release: UpdateClient.Release?
    @State private var binURL: URL?
    @State private var phase: Phase = .idle
    enum Phase { case idle, downloading, downloaded, uploading, rebooting, done, failed }

    private var current: String { status.fw ?? "—" }
    private var updateAvailable: Bool {
        guard let r = release else { return false }
        return UpdateClient.normalize(r.tag) != UpdateClient.normalize(status.fw)
    }

    var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text(L.fwCurrent(current)).foregroundStyle(palette.text)
                Text(L.fwLatest(release?.tag ?? "—")).foregroundStyle(palette.muted)

                if release != nil && !updateAvailable {
                    Label(L.fwUpToDate, systemImage: "checkmark.seal").foregroundStyle(palette.accent)
                } else if updateAvailable {
                    Button { Task { await downloadStep() } } label: { Label(L.fwDownload, systemImage: "arrow.down.circle") }
                        .buttonStyle(.bordered).tint(palette.accent).disabled(phase == .downloading)
                    if phase == .downloaded || phase == .uploading || phase == .rebooting {
                        Text(L.fwConnectCar).font(.footnote).foregroundStyle(palette.muted)
                        Button { Task { await flashStep() } } label: { Label(L.fwFlash, systemImage: "bolt.fill") }
                            .buttonStyle(.borderedProminent).tint(palette.accent)
                            .disabled(binURL == nil || !status.online || phase == .uploading || phase == .rebooting)
                    }
                }

                switch phase {
                case .downloading: ProgressView(L.fwDownloading)
                case .uploading: ProgressView(value: client.uploadProgress) { Text(L.fwUploading) }
                case .rebooting: ProgressView(L.fwRebooting)
                case .done: Label(L.fwDone, systemImage: "checkmark.circle.fill").foregroundStyle(palette.accent)
                case .failed: Text(L.fwFailed).foregroundStyle(palette.warn)
                default: EmptyView()
                }
                Spacer()
            }
            .padding()
        }
        .navigationTitle(L.settingsFirmware)
        .navigationBarTitleDisplayMode(.inline)
        .tint(palette.accent)
        .task { release = await client.latestRelease() }
    }

    private func downloadStep() async {
        guard let r = release else { return }
        phase = .downloading
        if let url = await client.download(r.assetURL) { binURL = url; phase = .downloaded }
        else { phase = .failed }
    }
    private func flashStep() async {
        guard let url = binURL else { return }
        phase = .uploading
        let ok = await client.upload(url)
        if ok { phase = .rebooting; try? await Task.sleep(nanoseconds: 6_000_000_000); phase = .done }
        else { phase = .failed }
    }
}
