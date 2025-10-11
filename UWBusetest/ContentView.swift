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
import CoreMotion
import SceneKit
import simd

// ==========================================================
// MARK: - App
// ==========================================================
@main
struct UWBusetestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// ==========================================================
// MARK: - Common Models / Views
// ==========================================================
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

// 2Dプロット（従来）
struct UWBPlotView: View {
    var positions: [CGPoint] // 相手の座標履歴を渡す

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 背景（座標軸）
                Rectangle().fill(Color(.systemBackground))
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

// 矢印（方角表示）
struct ArrowView: View {
    var direction: SIMD3<Float>? // x, y, z 方向ベクトル（デバイス座標系）

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
            if let dir = direction {
                // 画面上での回転角: y(上) を基準、x(右)で atan2
                let angle = atan2(Double(dir.x), Double(dir.y))
                ArrowShape()
                    .fill(Color.blue)
                    .rotationEffect(.radians(angle))
                    .animation(.easeInOut(duration: 0.25), value: angle)
            }
        }
    }
}

struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let len = rect.height * 0.4

        // 矢印の軸
        path.move(to: c)
        path.addLine(to: CGPoint(x: c.x, y: c.y - len))

        // 矢印の先端
        path.move(to: CGPoint(x: c.x - 6, y: c.y - len + 10))
        path.addLine(to: CGPoint(x: c.x, y: c.y - len))
        path.addLine(to: CGPoint(x: c.x + 6, y: c.y - len + 10))
        return path
    }
}

// ==========================================================
// MARK: - CoreMotion: 端末姿勢
// ==========================================================
final class MotionManager: ObservableObject {
    private let motion = CMMotionManager()
    @Published var attitude: CMAttitude? = nil

    init(updateInterval: TimeInterval = 0.05) {
        motion.deviceMotionUpdateInterval = updateInterval
        if motion.isDeviceMotionAvailable {
            // Z軸を地球の重力方向、Xは任意（ヨーが相対角になる）
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
                if let attitude = data?.attitude {
                    self?.attitude = attitude
                }
            }
        }
    }

    deinit {
        motion.stopDeviceMotionUpdates()
    }
}

// ==========================================================
// MARK: - SceneKit: 3D表示
// ==========================================================
/// UWBの direction と distance、端末姿勢（attitude）を使って相手の相対位置を 3D に配置
struct UWB3DView: UIViewRepresentable {
    var direction: SIMD3<Float>?
    var distance: Double?
    var attitude: CMAttitude?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        view.backgroundColor = .systemBackground

        // カメラ
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0.4, 2.0)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        view.scene?.rootNode.addChildNode(cameraNode)

        // 📱 スマホモデル（固定）
        let phone = SCNBox(width: 0.25, height: 0.5, length: 0.015, chamferRadius: 0.03)
        let mat = SCNMaterial()
//        mat.diffuse.contents = UIColor.systemBlue
        mat.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.3) // 半透明ブルー
        mat.metalness.contents = 0.2
        mat.roughness.contents = 0.1
        mat.isDoubleSided = true
        mat.blendMode = .alpha
        mat.transparencyMode = .dualLayer
        phone.materials = [mat]

        let phoneNode = SCNNode(geometry: phone)
        phoneNode.position = SCNVector3(0, 0.25, 0)
        phoneNode.name = "phone"
        view.scene?.rootNode.addChildNode(phoneNode)

        // 🌍 worldNode（相手・矢印・軸をまとめる親）
        let worldNode = SCNNode()
        worldNode.name = "world"
        view.scene?.rootNode.addChildNode(worldNode)

        // 相手（赤い球）
        let peer = SCNNode(geometry: SCNSphere(radius: 0.05))
        peer.geometry?.firstMaterial?.diffuse.contents = UIColor.systemRed
        peer.name = "peer"
        worldNode.addChildNode(peer)

        // 矢印
        let arrow = makeArrowNode()
        arrow.name = "arrow"
        worldNode.addChildNode(arrow)

        // 軸
        worldNode.addChildNode(makeAxisNode(length: 0.4, thickness: 0.006))

        return view
    }


    func updateUIView(_ view: SCNView, context: Context) {
        guard let scene = view.scene else { return }
        guard let worldNode = scene.rootNode.childNode(withName: "world", recursively: false),
              let peerNode = worldNode.childNode(withName: "peer", recursively: true),
              let arrowNode = worldNode.childNode(withName: "arrow", recursively: true)
        else { return }

        // ----- 姿勢（世界を回転させる） -----
        if let a = attitude {
            let roll = Float(a.roll)
            let pitch = Float(a.pitch)
            let yaw = Float(a.yaw)
            let qYaw   = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            let qPitch = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
            let qRoll  = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
            let q = qYaw * qPitch * qRoll
            let rot = SCNQuaternion(q.imag.x, q.imag.y, q.imag.z, q.real)
            worldNode.orientation = rot  // ←ここが「逆に動く」ポイント！
        }

        // ----- 相手位置 -----
        var dir = SIMD3<Float>(0, 0, -1)
        if let d = direction { dir = simd_normalize(d) }
        let d = Float(distance ?? 1.0)
        let pos = dir * d
        peerNode.position = SCNVector3(pos.x, pos.y, pos.z)

        // 矢印更新
        arrowNode.look(at: peerNode.position)
        let len = CGFloat(max(0.2, min(Double(d), 2.0)))
        if let shaft = arrowNode.childNode(withName: "shaft", recursively: true),
           let tip = arrowNode.childNode(withName: "tip", recursively: true) {
            shaft.scale = SCNVector3(1, 1, len)
            shaft.position = SCNVector3(0, 0, -Float(len)/2)
            tip.position = SCNVector3(0, 0, -Float(len))
        }
    }


    // 矢印と軸生成（同じ）
    private func makeArrowNode() -> SCNNode {
        let node = SCNNode()
        let shaft = SCNBox(width: 0.02, height: 0.02, length: 1.0, chamferRadius: 0)
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.geometry?.firstMaterial?.diffuse.contents = UIColor.systemBlue
        shaftNode.name = "shaft"
        shaftNode.position = SCNVector3(0, 0, -0.5)
        let tip = SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.1)
        let tipNode = SCNNode(geometry: tip)
        tipNode.name = "tip"
        tipNode.geometry?.firstMaterial?.diffuse.contents = UIColor.systemBlue
        tipNode.position = SCNVector3(0, 0, -1.0)
        tipNode.eulerAngles = SCNVector3(Float.pi/2, Float.pi, 0)
        node.addChildNode(shaftNode)
        node.addChildNode(tipNode)
        return node
    }

    private func makeAxisNode(length: CGFloat, thickness: CGFloat) -> SCNNode {
        let node = SCNNode()
        func line(_ color: UIColor) -> SCNNode {
            let box = SCNBox(width: thickness, height: thickness, length: length, chamferRadius: 0)
            let n = SCNNode(geometry: box)
            n.geometry?.firstMaterial?.diffuse.contents = color
            return n
        }
        let x = line(.systemRed)
        x.position = SCNVector3(Float(length/2), 0, 0)
        x.eulerAngles = SCNVector3(0, Float.pi/2, 0)
        let y = line(.systemGreen)
        y.position = SCNVector3(0, Float(length/2), 0)
        y.eulerAngles = SCNVector3(-Float.pi/2, 0, 0)
        let z = line(.systemBlue)
        z.position = SCNVector3(0, 0, Float(length/2))
        node.addChildNode(x)
        node.addChildNode(y)
        node.addChildNode(z)
        return node
    }
}

// ==========================================================
// MARK: - ContentView
// ==========================================================
struct ContentView: View {
    @StateObject private var nearbyManager = NearbyInteractionManager()
    @StateObject private var peerSession = MCPeerIDSession()
    @StateObject private var motionManager = MotionManager()

    @State private var showPermissionAlert = false

    // メッセージ送受信用
    @State private var message: String = ""
    @State private var receivedMessages: [String] = []

    // 2Dプロット用
    @State private var positions: [CGPoint] = []

    // 方角保持（未取得時に前の矢印を維持）
    @State private var lastStableDirection: SIMD3<Float>? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // タイトル
                HStack {
                    Text("Nearby Interaction Demo")
                        .font(.title2)
                        .bold()
                    Spacer()
                    Circle()
                        .fill(peerSession.isConnected ? .green : .red)
                        .frame(width: 10, height: 10)
                    Text(peerSession.isConnected ? "接続中" : "未接続")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 距離・方角（矢印）カード
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

                // セッション操作
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

                // 3D表示
                Text("3D可視化")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                UWB3DView(
                    direction: lastStableDirection ?? nearbyManager.lastDirection, // 安定化した方向
                    distance: nearbyManager.lastDistance,
                    attitude: motionManager.attitude
                )
                .frame(height: 300)
                .cornerRadius(12)
                .padding(.bottom, 8)

                Divider().padding(.vertical, 6)

                // メッセージ送受信
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

                // 2Dプロット
                UWBPlotView(positions: positions)
                    .frame(height: 300)
                    .padding()

                // ログ
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
                .frame(maxHeight: 280)

                Spacer(minLength: 8)
            }
            .padding()
        }
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
        // 方向・プロット更新
        .onChange(of: nearbyManager.lastDirection) { newDir in
            if let dir = newDir {
                // 矢印は方向が未取得になっても前回値で維持
                lastStableDirection = dir

                // 2Dプロットは x,y 成分のみ使用
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

// ==========================================================
// MARK: - NearbyInteraction Manager
// ==========================================================
final class NearbyInteractionManager: NSObject, ObservableObject, NISessionDelegate {
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

// ==========================================================
// MARK: - MultipeerConnectivity
// ==========================================================
final class MCPeerIDSession: NSObject, ObservableObject {
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

extension MCPeerIDSession: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.isConnected = (state == .connected)
        }
        log("\(peerID.displayName) の接続状態: \(state.rawValue)")
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
