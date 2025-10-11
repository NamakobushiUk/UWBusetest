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

// MARK: - UWBPlotView
struct UWBPlotView: View {
    var positions: [CGPoint]
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
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

                ForEach(positions.indices, id: \.self) { i in
                    let p = positions[i]
                    Circle()
                        .fill(i == positions.count - 1 ? Color.red : Color.blue)
                        .frame(width: 8, height: 8)
                        .position(
                            x: geo.size.width/2 + p.x * 50,
                            y: geo.size.height/2 - p.y * 50
                        )
                }
            }
        }
    }
}

// MARK: - ArrowView（方角表示）
struct ArrowView: View {
    var direction: SIMD3<Float>? // x, y, z方向ベクトル
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
            if let dir = direction {
                let angle = atan2(Double(dir.x), Double(dir.y))
                ArrowShape()
                    .fill(Color.blue)
                    .rotationEffect(.radians(angle))
                    .animation(.easeInOut(duration: 0.3), value: angle)
            }
        }
    }
}

struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let len = rect.height * 0.4
        path.move(to: c)
        path.addLine(to: CGPoint(x: c.x, y: c.y - len))
        path.move(to: CGPoint(x: c.x - 6, y: c.y - len + 10))
        path.addLine(to: CGPoint(x: c.x, y: c.y - len))
        path.addLine(to: CGPoint(x: c.x + 6, y: c.y - len + 10))
        return path
    }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var nearbyManager = NearbyInteractionManager()
    @StateObject private var peerSession = MCPeerIDSession()
    @State private var showPermissionAlert = false

    @State private var message: String = ""
    @State private var receivedMessages: [String] = []
    @State private var positions: [CGPoint] = []
    @State private var lastStableDirection: SIMD3<Float>? = nil // ← 方向保持
    
    var body: some View {
        VStack(spacing: 12) {
            // MARK: タイトル
            Text("Nearby Interaction Demo")
                .font(.title2)
                .bold()
            
            // MARK: 距離・方角カード
            VStack(spacing: 8) {
                if let d = nearbyManager.lastDistance {
                    Text(String(format: "距離: %.2f m", d))
                        .font(.headline)
                } else {
                    Text("距離: 未取得").font(.headline)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                    ArrowView(direction: lastStableDirection)
                        .frame(width: 100, height: 100)
                        .padding()
                }
                .frame(height: 120)
                .overlay(
                    Text(lastStableDirection == nil ? "方向: 未取得" : "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                )
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            
            // MARK: セッションボタン
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
                        peerSession.log("自分の token が未作成です。")
                    }
                }
                .disabled(!peerSession.isConnected || nearbyManager.myTokenData == nil)
                .padding(8)
                .background((!peerSession.isConnected || nearbyManager.myTokenData == nil) ? Color(.systemGray4) : Color(.systemGray5))
                .cornerRadius(8)
            }

            Divider().padding(.vertical, 6)

            // MARK: メッセージ送受信
            HStack {
                TextField("メッセージを入力", text: $message)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("送信") {
                    peerSession.sendMessage(message)
                    message = ""
                }
            }
            .padding(.vertical, 6)

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

            // MARK: プロット
            UWBPlotView(positions: positions)
                .frame(height: 300)
                .padding()

            // MARK: ログ
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
            peerSession.onPeerMessage = { text in receivedMessages.append(text) }
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
        // MARK: プロット更新
        .onChange(of: nearbyManager.lastDirection) { newDir in
            if let dir = newDir {
                lastStableDirection = dir // ← 前回の方向を保持
                if let dist = nearbyManager.lastDistance {
                    let x = CGFloat(dir.x) * CGFloat(dist)
                    let y = CGFloat(dir.y) * CGFloat(dist)
                    positions.append(CGPoint(x: x, y: y))
                }
            }
        }
        .alert("Nearby Interaction の許可が必要です", isPresented: $showPermissionAlert) {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("設定 → プライバシー → ローカルネットワーク でこのアプリのアクセスを許可してください。")
        }
    }

    private func sendMyTokenWithRetryIfNeeded(retryCount: Int, delay: TimeInterval) {
        guard retryCount > 0 else {
            peerSession.log("sendMyTokenWithRetryIfNeeded: 自分の token 返信に失敗")
            return
        }
        if let myToken = nearbyManager.myTokenData {
            peerSession.log("sendMyTokenWithRetryIfNeeded: 自分の token を返信 (\(myToken.count) bytes)")
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
        niSession?.invalidate()
        niSession = NISession()
        niSession?.delegate = self
        if let token = niSession?.discoveryToken {
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
                DispatchQueue.main.async { self.myTokenData = data }
                log("myTokenData 作成 (\(data.count) bytes)")
            } catch {
                log("トークンのアーカイブ失敗: \(error)")
            }
        } else {
            log("discoveryToken が取得できません。")
        }
    }

    func runMySession(peerTokenData: Data) {
        if niSession == nil {
            niSession = NISession()
            niSession?.delegate = self
            log("niSession 未作成 → 新規作成。")
        }
        do {
            let peerToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: peerTokenData)
            guard let token = peerToken else {
                log("peerToken nil")
                return
            }
            let config = NINearbyPeerConfiguration(peerToken: token)
            niSession?.run(config)
            log("NINearbyPeerConfiguration 実行")
        } catch {
            log("peerToken デコード失敗: \(error)")
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        let nsErr = error as NSError
        log("NISession invalidated: \(error.localizedDescription)")
        if nsErr.domain == "com.apple.NearbyInteraction" && nsErr.code == -5884 {
            DispatchQueue.main.async { self.permissionDeniedFlag = true }
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
            log("nearbyObjects 空")
            DispatchQueue.main.async {
                self.lastDistance = nil
                self.lastDirection = nil
            }
            return
        }
        if let dist = obj.distance {
            let d = Double(dist)
            DispatchQueue.main.async { self.lastDistance = d }
            log(String(format: "距離更新: %.3f m", d))
        }
        if let dir = obj.direction {
            DispatchQueue.main.async { self.lastDirection = dir }
            log(String(format: "方向更新: x %.3f y %.3f z %.3f", dir.x, dir.y, dir.z))
        }
    }
}

// MARK: - MCPeerIDSession（同上）
class MCPeerIDSession: NSObject, ObservableObject {
    private let peerID: MCPeerID
    private let serviceType = "ni-demo"
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    @Published var receivedTokenData: Data? = nil
    @Published var isConnected: Bool = false
    @Published var logs: [LogEntry] = []

    var onPeerMessage: ((String) -> Void)?

    override init() {
        self.peerID = MCPeerID(displayName: UIDevice.current.name)
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        self.browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        super.init()
        self.session.delegate = self
        self.advertiser.delegate = self
        self.browser.delegate = self
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        log("MC: 開始 (\(serviceType))")
    }

    deinit {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        log("MC: 停止済み")
    }

    func log(_ s: String) {
        let e = LogEntry(message: "[MC] \(s)")
        DispatchQueue.main.async {
            self.logs.append(e)
            if self.logs.count > 500 { self.logs.removeFirst(self.logs.count - 500) }
        }
        print(e.formatted)
    }

    func sendToken(_ data: Data) {
        guard !session.connectedPeers.isEmpty else { log("送信先なし"); return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            log("トークン送信成功 (\(data.count) bytes)")
        } catch { log("トークン送信失敗: \(error)") }
    }

    func sendMessage(_ text: String) {
        guard !session.connectedPeers.isEmpty else { log("送信先なし"); return }
        if let data = text.data(using: .utf8) {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
                log("メッセージ送信: \(text)")
            } catch { log("送信失敗: \(error)") }
        }
    }
}

extension MCPeerIDSession: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { self.isConnected = (state == .connected) }
        log("\(peerID.displayName) 状態: \(state.rawValue)")
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let text = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async { self.onPeerMessage?(text) }
            log("📩 受信 from \(peerID.displayName): \(text)")
        } else {
            DispatchQueue.main.async { self.receivedTokenData = data }
            log("トークン受信 (\(data.count) bytes)")
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        log("招待受信: \(peerID.displayName)")
        invitationHandler(true, session)
    }
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo: [String : String]?) {
        log("ピア発見: \(peerID.displayName)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        log("ピア喪失: \(peerID.displayName)")
    }
}
