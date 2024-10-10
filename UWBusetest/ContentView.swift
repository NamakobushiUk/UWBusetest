//  ContentView.swift
//  UWBusetest
//
//  Created by 小武右京 on 2024/10/10.
//

import SwiftUI
import NearbyInteraction
import MultipeerConnectivity

struct ContentView: View {
    @StateObject private var nearbyManager = NearbyInteractionManager()
    @StateObject private var peerSession = MCPeerIDSession()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")

            Button("セッション準備") {
                nearbyManager.prepareMySession()
            }
            .padding()

            Button("トークンを送信") {
                if let tokenData = nearbyManager.myTokenData {
                    peerSession.sendToken(tokenData)
                }
            }
            .disabled(!peerSession.isConnected || nearbyManager.myTokenData == nil)
            .padding()

            Button("セッション開始（受信トークンで）") {
                if let receivedData = peerSession.receivedTokenData {
                    nearbyManager.runMySession(peerTokenData: receivedData)
                }
            }
            .disabled(peerSession.receivedTokenData == nil)
            .padding()

            if let dist = nearbyManager.lastDistance {
                Text(String(format: "距離: %.2f m", dist))
            }
        }
        .padding()
    }
}

// MARK: - NearbyInteractionの管理クラス
class NearbyInteractionManager: NSObject, ObservableObject, NISessionDelegate {
    @Published var niSession: NISession? = nil
    @Published var myTokenData: Data? = nil
    @Published var lastDistance: Double? = nil

    // セッションを準備
    func prepareMySession() {
        guard NISession.isSupported else {
            print("Nearby Interaction はこのデバイスでサポートされていません。")
            return
        }

        // 新しいセッションを作成して delegate をセット
        niSession = NISession()
        niSession?.delegate = self

        // discoveryToken を安全にアーカイブ
        if let discoveryToken = niSession?.discoveryToken {
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: discoveryToken, requiringSecureCoding: true)
                DispatchQueue.main.async {
                    self.myTokenData = data
                }
                print("myTokenData を作成しました（\(data.count) bytes）")
            } catch {
                print("トークンのアーカイブに失敗: \(error)")
            }
        } else {
            print("discoveryToken が取得できませんでした。")
        }
    }

    // ピアから受信したトークンでセッションを開始
    func runMySession(peerTokenData: Data) {
        guard let session = niSession else {
            print("niSession が未準備です。prepareMySession を先に呼んでください。")
            return
        }

        do {
            let peerToken = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: peerTokenData)
            guard let token = peerToken else {
                print("トークンのデコード結果が nil でした。")
                return
            }
            let config = NINearbyPeerConfiguration(peerToken: token)
            // 追加の設定が必要ならここに（例: allowReporting = true など）
            session.run(config)
            print("NINearbyPeerConfiguration でセッションを実行しました。")
        } catch {
            print("トークンのデコードに失敗しました: \(error)")
        }
    }

    // MARK: - NISessionDelegate
    func session(_ session: NISession, didInvalidateWith error: Error) {
        print("NISession が無効化されました: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.lastDistance = nil
        }
    }

    // Nearby Interaction の近接情報が更新されたときのコールバック
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        // 通常は配列に 1 つのオブジェクト（1対1 の場合）が入る
        guard let obj = nearbyObjects.first else {
            DispatchQueue.main.async { self.lastDistance = nil }
            return
        }

        // obj.distance は Float? なので Double に変換して代入する
        if let floatDistance = obj.distance {
            let distanceAsDouble = Double(floatDistance)
            DispatchQueue.main.async {
                self.lastDistance = distanceAsDouble
            }
            print(String(format: "距離更新: %.3f m", distanceAsDouble))
        } else {
            DispatchQueue.main.async {
                self.lastDistance = nil
            }
            print("距離情報なし（角度のみ等）")
        }
    }
}

// MARK: - Multipeerセッション管理クラス
class MCPeerIDSession: NSObject, ObservableObject {
    private let peerID: MCPeerID
    private let serviceType = "ni-demo" // 1..15 文字、半角小文字・数字・ハイフンが使用可能
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    @Published var receivedTokenData: Data? = nil
    @Published var isConnected: Bool = false

    override init() {
        self.peerID = MCPeerID(displayName: UIDevice.current.name)
        self.session = MCSession(peer: self.peerID, securityIdentity: nil, encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(peer: self.peerID, discoveryInfo: nil, serviceType: serviceType)
        self.browser = MCNearbyServiceBrowser(peer: self.peerID, serviceType: serviceType)

        super.init()

        self.session.delegate = self
        self.advertiser.delegate = self
        self.browser.delegate = self

        // 両方開始しておけば同じアプリ同士で発見→接続しやすい
        self.advertiser.startAdvertisingPeer()
        self.browser.startBrowsingForPeers()
    }

    deinit {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    // トークンデータを送信
    func sendToken(_ data: Data) {
        guard session.connectedPeers.count > 0 else {
            print("送信先のピアがいません。")
            return
        }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            print("トークン送信成功（\(data.count) bytes）")
        } catch {
            print("トークン送信失敗: \(error)")
        }
    }
}

// MARK: - MCSessionDelegate / MCNearbyServiceAdvertiserDelegate / MCNearbyServiceBrowserDelegate
extension MCPeerIDSession: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    // MCSessionDelegate
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.isConnected = (state == .connected)
        }
        print("\(peerID.displayName) の接続状態: \(state.rawValue)")
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.receivedTokenData = data
        }
        print("データ受信: \(data.count) bytes from \(peerID.displayName)")
    }

    // 未使用のメソッド（必須なので空実装）
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    // MCNearbyServiceAdvertiserDelegate
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("招待を受信: \(peerID.displayName)。自動承認します。")
        invitationHandler(true, self.session)  // 自動的に承認して既存の session を渡す
    }

    // MCNearbyServiceBrowserDelegate: ピアを発見したら招待を送る
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("ピア発見: \(peerID.displayName) — 自動で招待を送信します。")
        browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("ピア喪失: \(peerID.displayName)")
    }
}
