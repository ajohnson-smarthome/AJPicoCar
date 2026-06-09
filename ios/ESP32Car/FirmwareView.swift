import SwiftUI

struct FirmwareView: View {
    let palette: Palette
    @ObservedObject var status: CarStatus
    @StateObject private var client = UpdateClient()

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
        VStack(alignment: .leading, spacing: 7) {
            switch phase {
            case .checking:
                title(L.fwChecking); sub(L.fwCurrent(current))
            case .upToDate:
                title(L.fwUpToDate); sub(L.fwVersionLine(current))
                Button { Task { await check() } } label: { Text(L.fwRecheck) }
                    .buttonStyle(.bordered).tint(p.muted).padding(.top, 2)
            case .available:
                title(L.fwAvailable); sub(L.fwTransition(current, release?.tag ?? "—"))
                Button { Task { await download() } } label: { Text(L.fwUpdate) }
                    .buttonStyle(.borderedProminent).tint(p.accent).padding(.top, 2)
            case .downloading:
                title(L.fwDownloadTitle)
                sub("\(L.fwTransition(current, release?.tag ?? "")) · \(Int(client.downloadProgress * 100))%")
                ProgressView(value: client.downloadProgress).tint(p.accent).frame(width: 150)
            case .downloaded:
                title(L.fwConnectTitle); sub(L.fwConnectSub)
                Button { Task { await flash() } } label: { Text(L.fwFlash) }
                    .buttonStyle(.borderedProminent).tint(p.accent).disabled(!status.online).padding(.top, 2)
            case .uploading:
                title(L.fwUploadTitle)
                sub("\(release?.tag ?? "") · \(Int(client.uploadProgress * 100))%")
                ProgressView(value: client.uploadProgress).tint(p.accent).frame(width: 150)
            case .rebooting:
                title(L.fwRebootTitle); sub(L.fwRebootWait)
            case .done:
                title(L.fwDoneTitle); sub(L.fwDoneSub(current))
            case .failed:
                title(L.fwFailTitle); sub(L.fwFailSub)
                Button { Task { await check() } } label: { Text(L.fwRetry) }
                    .buttonStyle(.borderedProminent).tint(p.accent).padding(.top, 2)
            }
        }
    }

    private func title(_ t: String) -> some View {
        Text(t).font(.system(size: 16, weight: .semibold)).foregroundStyle(p.text)
    }
    private func sub(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).foregroundStyle(p.muted)
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
