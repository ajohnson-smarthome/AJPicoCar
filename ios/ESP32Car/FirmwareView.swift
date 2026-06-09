import SwiftUI

struct FirmwareView: View {
    let palette: Palette
    @ObservedObject var status: CarStatus
    @StateObject private var client = UpdateClient()
    @Environment(\.dismiss) private var dismiss

    @State private var release: UpdateClient.Release?
    @State private var binURL: URL?
    @State private var phase: FwPhase = .checking

    private var current: String { status.fw ?? "—" }
    private var p: Palette { palette }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()
            HStack(spacing: 24) {
                FirmwareCarView(phase: phase, palette: p)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                stateBlock
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
        .navigationTitle(L.settingsFirmware)
        .navigationBarTitleDisplayMode(.inline)
        .tint(p.accent)
        .task { await check() }
    }

    @ViewBuilder private var stateBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch phase {
            case .checking:
                Text(L.fwCurrent(current)).foregroundStyle(p.text)
                ProgressView(L.fwChecking).tint(p.accent)
            case .upToDate:
                Text(L.fwCurrent(current)).foregroundStyle(p.text)
                Label(L.fwUpToDate, systemImage: "checkmark.seal").foregroundStyle(p.accent)
                Button { Task { await check() } } label: { Label(L.fwRecheck, systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).tint(p.muted)
            case .available:
                Text(L.fwCurrent(current)).foregroundStyle(p.text)
                Text(L.fwLatest(release?.tag ?? "—")).foregroundStyle(p.accent)
                Button { Task { await download() } } label: { Label(L.fwUpdate, systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderedProminent).tint(p.accent)
            case .downloading:
                Text("\(current) → \(release?.tag ?? "")").font(.subheadline).foregroundStyle(p.muted)
                Text(L.fwDownloadingGh).font(.caption).foregroundStyle(p.muted)
                ProgressView().tint(p.accent)
            case .downloaded:
                Label(L.fwDownloaded(release?.tag ?? ""), systemImage: "checkmark.circle").foregroundStyle(p.accent)
                Text(L.fwConnectCar).font(.caption).foregroundStyle(p.warn)
                Button { Task { await flash() } } label: { Label(L.fwFlash, systemImage: "bolt.fill") }
                    .buttonStyle(.borderedProminent).tint(p.accent)
                    .disabled(!status.online)
            case .uploading:
                Text(L.fwUploadingTag(release?.tag ?? "")).font(.subheadline).foregroundStyle(p.muted)
                ProgressView(value: client.uploadProgress).tint(p.accent).frame(width: 160)
                Text("\(Int(client.uploadProgress * 100))%").font(.caption).foregroundStyle(p.muted)
            case .rebooting:
                ProgressView(L.fwRebooting).tint(p.accent)
                Text(L.fwRebootWait).font(.caption).foregroundStyle(p.muted)
            case .done:
                Label(L.fwDone, systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(p.accent)
                Text(L.fwVersion(current)).foregroundStyle(p.text)
                Button { dismiss() } label: { Text(L.close) }
                    .buttonStyle(.bordered).tint(p.muted)
            case .failed:
                Label(L.fwFailed, systemImage: "xmark.circle").font(.headline).foregroundStyle(p.warn)
                Button { Task { await check() } } label: { Label(L.fwRetry, systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent).tint(p.accent)
            }
        }
    }

    private func check() async {
        phase = .checking
        let r = await client.latestRelease()
        release = r
        guard let r else { phase = .failed; return }
        phase = (UpdateClient.normalize(r.tag) != UpdateClient.normalize(status.fw)) ? .available : .upToDate
    }
    private func download() async {
        guard let r = release else { return }
        phase = .downloading
        if let url = await client.download(r.assetURL) { binURL = url; phase = .downloaded }
        else { phase = .failed }
    }
    private func flash() async {
        guard let url = binURL else { return }
        phase = .uploading
        guard await client.upload(url) else { phase = .failed; return }
        phase = .rebooting
        var sawOffline = false
        let deadline = Date.now.addingTimeInterval(25)
        while Date.now < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !status.online { sawOffline = true }
            else if sawOffline { phase = .done; return }
        }
        phase = .failed
    }
}
