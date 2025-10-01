//
//  UWBusetestApp.swift
//  UWBusetest
//
//  Created by 小武右京 on 2024/10/10.
//

import SwiftUI
import NearbyInteraction
import MultipeerConnectivity
import UIKit // for opening Settings

@main
struct UWBusetestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - LogEntry
struct LogEntry: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let message: String

    init(message: String, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.message = message
    }

    var formatted: String {
        let t = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)
        return "\(t) - \(message)"
    }
}

struct UWBPlotView: View {
    var positions: [CGPoint] // 相手の座標履歴を渡す
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 背景（座標軸）
                Rectangle()
                    .fill(Color(.systemBackground))
                Path { path in
                    let midX = geo.size.width / 2
                    let midY = geo.size.height / 2
                    path.move(to: CGPoint(x: midX, y: 0))
                    path.addLine(to: CGPoint(x: midX, y: geo.size.height))
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: midY))
                }
                .stroke(Color.gray.opacity(0.5), lineWidth: 1)

                // 相手の位置履歴
                ForEach(positions.indices, id: \.self) { i in
                    let p = positions[i]
                    Circle()
                        .fill(i == positions.count - 1 ? Color.red : Color.blue)
                        .frame(width: 8, height: 8)
                        .position(
                            x: geo.size.width/2 + p.x * 50, // スケール調整
                            y: geo.size.height/2 - p.y * 50
                        )
                }
            }
        }
    }
}



// MARK: - ContentView (全体)
struct ContentView: View {
    @StateObject private var nearbyManager = NearbyInteractionManager()
    @StateObject private var peerSession = MCPeerIDSession()

    @State private var showPermissionAlert = false

    // メッセージ送受信用
    @State private var message: String = ""
    @State private var receivedMessages: [String] = []

    //位置情報プロット用
    @State private var positions: [CGPoint] = []


    var body: some View {
        VStack(spacing: 12) {
            Text("Nearby Interaction Demo")
                .font(.title2)
                .bold()

            // 距離表示
            Group {
                if let d = nearbyManager.lastDistance {
                    Text(String(format: "距離: %.2f m", d))
                        .font(.headline)
                } else {
                    Text("距離: 未取得")
                        .font(.headline)
                }
            }

            // 方向表示
            Group {
                if let dir = nearbyManager.lastDirection {
                    Text(String(format: "方向: x %.2f  y %.2f  z %.2f", dir.x, dir.y, dir.z))
                        .font(.subheadline)
                } else {
                    Text("方向: 未取得")
                        .font(.subheadline)
                }
            }

            HStack(spacing: 12) {
                Button("セッション準備") {
                    nearbyManager.prepareMySession()
                }
                .padding(8)
                .background(Color(.systemGray5))
                .cornerRadius(8)

                Button("トークン送信（手動）") {
                    if let data = nearbyManager.myTokenData {
                        peerSession.sendToken(data)
                    } else {
                        peerSession.log("自分の token が未作成です。先にセッション準備をしてください。")
                    }
                }
                .disabled(!peerSession.isConnected || nearbyManager.myTokenData == nil)
                .padding(8)
                .background((!peerSession.isConnected || nearbyManager.myTokenData == nil) ? Color(.systemGray4) : Color(.systemGray5))
                .cornerRadius(8)
            }

            Divider().padding(.vertical, 6)

            // メッセージ送信欄
            HStack {
                TextField("メッセージを入力", text: $message)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("送信") {
                    peerSession.sendMessage(message)
                    message = ""
                }
            }
            .padding(.vertical, 6)

            // 受信メッセージ表示
            VStack(alignment: .leading, spacing: 4) {
                ForEach(receivedMessages, id: \.self) { msg in
                    Text("📩 \(msg)")
                        .font(.footnote)
                        .padding(4)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(6)
                }
            }
            .frame(maxHeight: 150)

            Divider().padding(.vertical, 6)

            UWBPlotView(positions: positions)
                .frame(height: 300)
                .padding()

            // ログ表示（スクロール）
            Text("ログ")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(mergedLogs(), id: \.id) { entry in
                        Text(entry.formatted)
                            .font(.caption2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(6)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 300)

            Spacer()
        }
        .padding()
        .onAppear {
            nearbyManager.prepareMySession()
            peerSession.log("onAppear: prepareMySession() 呼び出し済み")

            // メッセージ受信ハンドラ設定
            peerSession.onPeerMessage = { text in
                receivedMessages.append(text)
            }
        }
        .onChange(of: peerSession.receivedTokenData) { newData in
            guard let data = newData else { return }
            nearbyManager.log("ContentView observed receivedTokenData (\(data.count) bytes)")
            nearbyManager.runMySession(peerTokenData: data)
            sendMyTokenWithRetryIfNeeded(retryCount: 6, delay: 0.5)
        }
        .onChange(of: nearbyManager.permissionDeniedFlag) { v in
            if v { showPermissionAlert = true }
        }
        //プロットグラフ
        .onChange(of: nearbyManager.lastDirection) { newDir in
            if let dir = newDir, let dist = nearbyManager.lastDistance {
                let x = CGFloat(dir.x) * CGFloat(dist)
                let y = CGFloat(dir.y) * CGFloat(dist)
                positions.append(CGPoint(x: x, y: y))
            }
        }

        .alert("Nearby Interaction の許可が必要です", isPresented: $showPermissionAlert) {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("設定 → プライバシー → ローカルネットワーク でこのアプリのアクセスを許可してください。")
        }
    }

    private func sendMyTokenWithRetryIfNeeded(retryCount: Int, delay: TimeInterval) {
        guard retryCount > 0 else {
            peerSession.log("sendMyTokenWithRetryIfNeeded: 自分の token 返信に失敗（timeout）")
            return
        }
        if let myToken = nearbyManager.myTokenData {
            peerSession.log("sendMyTokenWithRetryIfNeeded: 自分の token を返信します (\(myToken.count) bytes)")
            peerSession.sendToken(myToken)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.sendMyTokenWithRetryIfNeeded(retryCount: retryCount - 1, delay: delay)
            }
        }
    }

    private func mergedLogs() -> [LogEntry] {
        let all = nearbyManager.logs + peerSession.logs
        return all.sorted { $0.date < $1.date }
    }
}

// MARK: - NearbyInteractionManager
class NearbyInteractionManager: NSObject, ObservableObject, NISessionDelegate {
    @Published var niSession: NISession? = nil
    @Published var myTokenData: Data? = nil
    @Published var lastDistance: Double? = nil
    @Published var lastDirection: SIMD3<Float>? = nil
    @Published var logs: [LogEntry] = []
    @Published var permissionDeniedFlag: Bool = false

    func log(_ s: String) {
        let entry = LogEntry(message: "[NI] \(s)")
        DispatchQueue.main.async {
            self.logs.append(entry)
            if self.logs.count > 500 { self.logs.removeFirst(self.logs.count - 500) }
        }
        print(entry.formatted)
    }

    func prepareMySession() {
        guard NISession.isSupported else {
            log("NISession はこのデバイスでサポートされていません。")
            return
        }
        if niSession != nil {
            niSession?.invalidate()
            niSession = nil
        }
        niSession = NISession()
        niSession?.delegate = self
        if let discoveryToken = niSession?.discoveryToken {
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: discoveryToken, requiringSecureCoding: true)
                DispatchQueue.main.async { self.myTokenData = data }
                log("myTokenData を作成しました（\(data.count) bytes）")
            } catch {
                log("トークンのアーカイブに失敗: \(error)")
            }
        } else {
            log("discoveryToken が取得できませんでした。")
        }
    }

    func runMySession(peerTokenData: Data) {
        if niSession == nil {
            niSession = NISession()
            niSession?.delegate = self
            log("runMySession: niSession が未作成だったため新規作成しました。")
        }
        do {
            let peerToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: peerTokenData)
            guard let token = peerToken else {
                log("peerToken のデコード結果が nil でした。")
                return
            }
            let config = NINearbyPeerConfiguration(peerToken: token)
            niSession?.run(config)
            log("NINearbyPeerConfiguration を run しました。")
        } catch {
            log("peerToken のデコードに失敗しました: \(error)")
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        let nsErr = error as NSError
        log("NISession invalidated. localizedDescription: \(error.localizedDescription)")
        if nsErr.domain == "com.apple.NearbyInteraction" && nsErr.code == -5884 {
            DispatchQueue.main.async { self.permissionDeniedFlag = true }
            log("Nearby Interaction の許可が拒否されています")
        }
        DispatchQueue.main.async {
            self.lastDistance = nil
            self.lastDirection = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.prepareMySession()
        }
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let obj = nearbyObjects.first else {
            log("nearbyObjects が空です。")
            DispatchQueue.main.async {
                self.lastDistance = nil
                self.lastDirection = nil
            }
            return
        }
        if let floatDistance = obj.distance {
            let d = Double(floatDistance)
            DispatchQueue.main.async { self.lastDistance = d }
            log(String(format: "距離更新: %.3f m", d))
        } else {
            DispatchQueue.main.async { self.lastDistance = nil }
            log("距離情報がありません。")
        }
        if let dir = obj.direction {
            DispatchQueue.main.async { self.lastDirection = dir }
            log(String(format: "方向更新: x:%.3f y:%.3f z:%.3f", dir.x, dir.y, dir.z))
        } else {
            DispatchQueue.main.async { self.lastDirection = nil }
            log("方向情報がありません。")
        }
    }
}

// MARK: - MCPeerIDSession
class MCPeerIDSession: NSObject, ObservableObject {
    private let peerID: MCPeerID
    private let serviceType = "ni-demo"
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    @Published var receivedTokenData: Data? = nil
    @Published var isConnected: Bool = false
    @Published var logs: [LogEntry] = []

    // メッセージ受信ハンドラ
    var onPeerMessage: ((String) -> Void)?

    override init() {
        self.peerID = MCPeerID(displayName: UIDevice.current.name)
        self.session = MCSession(peer: self.peerID, securityIdentity: nil, encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(peer: self.peerID, discoveryInfo: nil, serviceType: serviceType)
        self.browser = MCNearbyServiceBrowser(peer: self.peerID, serviceType: serviceType)

        super.init()

        self.session.delegate = self
        self.advertiser.delegate = self
        self.browser.delegate = self

        self.advertiser.startAdvertisingPeer()
        self.browser.startBrowsingForPeers()
        log("MC: advertiser & browser 開始 (serviceType: \(serviceType))")
    }

    deinit {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        log("MC: deinit - stopped advertising/browsing and disconnected")
    }

    func log(_ s: String) {
        let entry = LogEntry(message: "[MC] \(s)")
        DispatchQueue.main.async {
            self.logs.append(entry)
            if self.logs.count > 500 { self.logs.removeFirst(self.logs.count - 500) }
        }
        print(entry.formatted)
    }

    func sendToken(_ data: Data) {
        guard session.connectedPeers.count > 0 else {
            log("送信先ピアがいません。")
            return
        }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            log("トークン送信成功 (\(data.count) bytes)")
        } catch {
            log("トークン送信失敗: \(error)")
        }
    }

    func sendMessage(_ text: String) {
        guard session.connectedPeers.count > 0 else {
            log("送信先ピアがいません。")
            return
        }
        if let data = text.data(using: .utf8) {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
                log("メッセージ送信成功: \(text)")
            } catch {
                log("メッセージ送信失敗: \(error)")
            }
        }
    }
}

// MARK: - MC Delegates
extension MCPeerIDSession: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.isConnected = (state == .connected)
        }
        log("\(peerID.displayName) の接続状態: \(state.rawValue)")
        
//        //自動で再接続を試みる
//        if state == .notConnected {
//            // 接続が切れたら再探索
//            log("接続が切れたので再探索を開始します")
//            advertiser.stopAdvertisingPeer()
//            browser.stopBrowsingForPeers()
//            advertiser.startAdvertisingPeer()
//            browser.startBrowsingForPeers()
//        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let text = String(data: data, encoding: .utf8) {
            // UTF-8 として解釈できればメッセージ
            DispatchQueue.main.async {
                self.onPeerMessage?(text)
            }
            log("📩 メッセージ受信 from \(peerID.displayName): \(text)")
        } else {
            // それ以外はトークンデータとして扱う
            DispatchQueue.main.async {
                self.receivedTokenData = data
            }
            log("トークンデータ受信: \(data.count) bytes from \(peerID.displayName)")
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        log("招待を受信: \(peerID.displayName) — 自動承認します。")
        invitationHandler(true, self.session)
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        log("ピア発見: \(peerID.displayName) — 自動で招待を送信します。")
        browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        log("ピア喪失: \(peerID.displayName)")
    }
}
