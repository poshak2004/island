import AppKit
import IslandCore
import SceneKit
import SwiftUI

/// Hosts the 3D AirPods scene with a transparent background. GPU-rendered only while visible.
struct AirPodsSceneView: NSViewRepresentable {
    var model: AirPodsSceneBuilder.Model
    var reduceMotion = false
    /// Delay before the sequence starts — lets the Island finish opening first.
    var startDelay: TimeInterval = 0.45

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        v.backgroundColor = .clear
        v.wantsLayer = true
        v.layer?.isOpaque = false
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.isPlaying = true
        v.allowsCameraControl = false
        v.scene = AirPodsSceneBuilder.make(model: model, animate: !reduceMotion, startDelay: startDelay)
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {}

    static func dismantleNSView(_ v: SCNView, coordinator: ()) {
        v.isPlaying = false
        v.scene = nil
    }
}

/// Expanded card shown when AirPods (or other headphones) connect: the 3D case centred on top,
/// name and status underneath — concentric with the Island, like the iPhone's connect card.
struct DeviceConnectedView: View {
    let device: DeviceActivity
    let id: String
    @Environment(\.islandReduceMotion) private var reduceMotion
    @Environment(\.islandCommands) private var send
    @State private var appeared = false

    private var airPodsModel: AirPodsSceneBuilder.Model? {
        let n = device.name.lowercased()
        guard n.contains("airpods"), !n.contains("max") else { return nil }
        return n.contains("pro") ? .pro : .standard
    }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let model = airPodsModel, device.connected {
                    AirPodsSceneView(model: model, reduceMotion: reduceMotion)
                } else {
                    Image(systemName: DevicePresentation.symbol(device))
                        .font(.system(size: 52, weight: .regular))
                        .foregroundStyle(.white)
                        .rotation3DEffect(.degrees(appeared || reduceMotion ? 0 : -70), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
                }
            }
            .frame(width: 140, height: 110)

            VStack(spacing: 3) {
                Text(device.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: device.connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(device.connected ? IslandPalette.batteryGood : .white.opacity(0.6))
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.2)
                    Text(device.connected ? "Connected" : "Disconnected")
                        .foregroundStyle(IslandPalette.secondaryText)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 6)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            IslandIconButton(symbol: "xmark", size: 11, label: "Dismiss") { send(.ui(.dismiss(activityID: id))) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name) \(device.connected ? "connected" : "disconnected")")
        .onAppear {
            // Text follows the 3D sequence (lid opens ≈ 0.95 s after the card appears).
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(reduceMotion ? 0 : 0.9)) { appeared = true }
        }
    }
}

/// Compact trailing: a green check instead of text.
struct DeviceCompactTrailing: View {
    let device: DeviceActivity
    var body: some View {
        Image(systemName: device.connected ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(device.connected ? IslandPalette.batteryGood : .white.opacity(0.55))
            .accessibilityHidden(true)
    }
}
