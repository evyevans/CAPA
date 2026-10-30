import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import CapaCore

// Dependency-free smoke checks for hosts with Swift but without Xcode/XCTest.
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError("FAIL: \(label)") }
    print("PASS: \(label)")
}

var policy = DeliveryPolicy(available: false)
check(!policy.begin("a"), "opt-out prevents incoming speech")
check(policy.acknowledged.isEmpty, "suppressed delivery remains unacknowledged")
policy.available = true
check(policy.begin("a"), "enabled delivery starts")
check(!policy.begin("a") && !policy.begin("b"), "duplicates and concurrent utterances are suppressed")
policy.interrupted()
check(policy.begin("a"), "interrupted delivery can be retried")
policy.finished("a")
check(!policy.begin("a"), "completed playback does not repeat")
var memo = PendingMemo(text: "Research recycling")
let original = memo.requestID
memo.markSending(); memo.markUnconfirmed()
let restored = try JSONDecoder().decode(PendingMemo.self, from: JSONEncoder().encode(memo))
check(restored.requestID == original && !restored.canDiscard, "ambiguous submission keeps its identity across restart")
memo.accept(runID: nil)
check(memo.phase == .unconfirmed, "acceptance requires a Hermes run ID")
memo.accept(runID: "run-1")
check(memo.phase == .accepted, "accepted work records confirmation")
print("9 core checks passed")

let approvalJSON = #"{"kind":"approval","prompt_id":"p1","execution_generation":7,"command":"send_email --to client@example.com","description":"","choices":["once","deny"],"edit":{"path":"report.md","old_text":"before","new_text":"after"}}"#
let approval = try JSONDecoder().decode(AgentControl.self, from: Data(approvalJSON.utf8))
check(approval.label.contains("send_email"), "approval exposes exact command even when description is empty")
check(approval.editDescription?.contains("report.md") == true, "approval retains structured edit details")
check(approval.canApproveOnce, "approval respects advertised one-time choice")
let denyOnly = try JSONDecoder().decode(AgentControl.self, from: Data(#"{"kind":"approval","prompt_id":"p2","execution_generation":1,"command":"blocked","choices":["deny"]}"#.utf8))
check(!denyOnly.canApproveOnce, "approval cannot offer an unavailable choice")
let question = try JSONDecoder().decode(AgentControl.self, from: Data(#"{"kind":"clarify","prompt_id":"p3","execution_generation":8,"question":"Which region?","choices":[]}"#.utf8))
let reply = ClarificationReply(taskID: "existing-task", control: question)!
let savedReply = try JSONDecoder().decode(ClarificationReply.self, from: JSONEncoder().encode(reply))
check(savedReply.taskID == "existing-task" && savedReply.control.id == "p3" && savedReply.control.executionGeneration == 8,
      "saved voice reply retains its exact task and clarification generation")
check(ClarificationReply(taskID: "existing-task", control: approval) == nil,
      "voice reply mode cannot authorize an approval")
print("15 core checks passed")

let identity = try JSONDecoder().decode(WorkspaceIdentity.self, from: Data(#"{"device_id":"mac","workspace_id":"home","name":"My Hermes","reply_mode":"notifications","preferred_device_id":"phone"}"#.utf8))
check(identity.workspace_id == "home" && identity.preferred_device_id == "phone", "shared workspace and destination decode from bridge contract")
let inventory = try JSONDecoder().decode(ConnectionInventory.self, from: Data(#"{"discovery_available":true,"toolsets":[{"name":"core","enabled":true,"configured":false,"tools":["read_file"]}],"skills":[],"message":"Configured in Hermes"}"#.utf8))
check(inventory.toolsets[0].status == "Needs setup in Hermes", "discovered but unconfigured toolset does not claim connection")
let unknown = try JSONDecoder().decode(AgentConnection.self, from: Data(#"{"name":"custom"}"#.utf8))
check(unknown.status.contains("unknown"), "missing tool availability remains unknown")
print("18 core checks passed")

check((try? BridgeClient.validatedBaseURL("http://127.0.0.1:8787", platform: "macos")) != nil,
      "Mac can connect directly to its local bridge")
check((try? BridgeClient.validatedBaseURL("http://example.com:8787", platform: "macos")) == nil,
      "Mac refuses unencrypted remote bridges")
check((try? BridgeClient.validatedBaseURL("http://127.0.0.1:8787", platform: "ios")) == nil,
      "iPhone still requires trusted HTTPS")
check((try? BridgeClient.validatedBaseURL("http://localhost.evil.test", platform: "macos")) == nil,
      "loopback lookalike domains are refused")
check((try? BridgeClient.validatedBaseURL("https://user:secret@example.com", platform: "macos")) == nil,
      "credentials embedded in bridge addresses are refused")
print("23 core checks passed")

let silence = VoiceSignal.measure(samples: [Float](repeating: 0, count: 4096), sampleRate: 48000)
check(silence.level == 0 && silence.pitch == 0, "silence never animates a pretend voice")
func tone(_ frequency: Double, amplitude: Double = 0.2) -> [Float] {
    (0..<4096).map { Float(amplitude * sin(2 * Double.pi * frequency * Double($0) / 48000)) }
}
let low = VoiceSignal.measure(samples: tone(110), sampleRate: 48000)
let mid = VoiceSignal.measure(samples: tone(220), sampleRate: 48000)
let high = VoiceSignal.measure(samples: tone(440), sampleRate: 48000)
check(abs(low.pitch - 110) < 8 && abs(mid.pitch - 220) < 12 && abs(high.pitch - 440) < 24,
      "voice animation follows measured low, medium and high pitch")
check(VoiceSignal.measure(samples: tone(220, amplitude: 0.6), sampleRate: 48000).level >
      VoiceSignal.measure(samples: tone(220, amplitude: 0.02), sampleRate: 48000).level,
      "voice animation strength follows recorded loudness")
check(VoiceSignal.measure(samples: [Float.nan, Float.infinity], sampleRate: 0).level == 0,
      "invalid input cannot produce nonfinite animation")
check(RecorderIntent.resolve(recording: false, preparing: false, processing: false, speaking: false,
      pending: false, hasDraft: false, saved: true) == .reviewMemo, "saved audio opens recovery rather than silently ignoring a click")
check(RecorderIntent.resolve(recording: false, preparing: false, processing: false, speaking: false,
      pending: true, hasDraft: false, saved: false) == .reviewMemo, "unconfirmed requests require review before new capture")
check(RecorderIntent.resolve(recording: false, preparing: true, processing: false, speaking: false,
      pending: false, hasDraft: false, saved: false) == .wait, "double clicks during microphone permission cannot start overlapping recordings")
print("30 core checks passed")

check(SpeechLocaleChoice.select(preferred: "en_GB@rg=cazzzz", language: "en", region: "CA", installed: ["en-US", "en-CA"]) == "en-CA",
      "Canadian installed model handles unavailable British English locale")
check(SpeechLocaleChoice.select(preferred: "fr_FR", language: "fr", region: "CA", installed: ["en-US"]) == nil,
      "missing speech assets never silently switch to a different language")
check(SpeechLocaleChoice.select(preferred: "en_GB", language: "en", region: "CA", installed: ["en-GB", "en-CA"]) == "en-GB",
      "available preferred speech locale is retained")
print("33 core checks passed")

check(CompactWidgetGeometry.action(x: 52, y: 15, capturing: false) == .record,
      "center waveform starts recording")
check(CompactWidgetGeometry.action(x: 92, y: 15, capturing: false) == .openApp,
      "arrow opens the app without recording")
check(CompactWidgetGeometry.action(x: 81, y: 15, capturing: false) == .none,
      "gap between microphone and arrow has no action")
check(CompactWidgetGeometry.action(x: 92, y: 15, capturing: true) == .none,
      "arrow cannot navigate accidentally during capture")
check(CompactWidgetGeometry.action(x: 52, y: 15, capturing: true) == .record,
      "recording target remains active to stop and send")
print("38 core checks passed")

let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
let panel = CGSize(width: 132, height: 42)
check(WidgetPlacement.origin(screen: display, usable: CGRect(x: 0, y: 78, width: 1470, height: 853), panel: panel).y == 78,
      "visible bottom Dock reservation lifts the widget")
check(WidgetPlacement.origin(screen: display, usable: display, panel: panel).y == 0,
      "hidden Dock reclaims the screen edge")
check(WidgetPlacement.origin(screen: display, usable: display, panel: panel,
      dock: [CGRect(x: 200, y: 0, width: 1000, height: 90)]).y == 90,
      "revealed auto-hide Dock lifts the widget even when visibleFrame stays unchanged")
check(WidgetPlacement.origin(screen: display, usable: CGRect(x: 80, y: 0, width: 1390, height: 931), panel: panel,
      dock: [CGRect(x: 0, y: 0, width: 80, height: 956)]).y == 0,
      "side Dock does not create a false bottom reservation")
check(WidgetPlacement.origin(screen: CGRect(x: -1470, y: -956, width: 1470, height: 956),
      usable: CGRect(x: -1470, y: -870, width: 1470, height: 870), panel: panel).y == -870,
      "display below primary retains its global coordinate origin")
check(WidgetPlacement.origin(screen: display, usable: display, panel: panel,
      dock: [CGRect(x: -1400, y: 0, width: 1000, height: 90)]).y == 0,
      "Dock on another display cannot move this widget")
check(WidgetPlacement.origin(screen: display, usable: display, panel: panel,
      dock: [CGRect(x: 200, y: 200, width: 1000, height: 90)]).y == 0,
      "floating Dock-owned windows do not masquerade as the Dock")
check(WidgetPlacement.appKitRect(CGRect(x: 300, y: 866, width: 900, height: 90), primaryTop: 956).minY == 0,
      "WindowServer coordinates convert to AppKit bottom origin")
print("46 core checks passed")

check(WidgetPlacement.clamped(CGPoint(x: 600, y: 400), usable: display, panel: panel) == CGPoint(x: 600, y: 400),
      "custom position stays where the user dropped it")
check(WidgetPlacement.clamped(CGPoint(x: -40, y: -40), usable: CGRect(x: 0, y: 60, width: 1470, height: 863), panel: panel) == CGPoint(x: 0, y: 60),
      "custom position stays within usable display bounds")
check(WidgetPlacement.clamped(CGPoint(x: 4000, y: 4000), usable: display, panel: panel) == CGPoint(x: 1338, y: 914),
      "disconnected display positions return to a reachable screen")
print("49 core checks passed")

check(CompactWidgetGeometry.click(startX: 77.9, startY: 15, endX: 82.1, endY: 15, capturing: false) == .none,
      "subthreshold jitter from recording to arrow cannot open the hub")
check(CompactWidgetGeometry.click(startX: 81, startY: 15, endX: 83, endY: 15, capturing: false) == .none,
      "pressing a neutral gap cannot activate a button on release")
check(CompactWidgetGeometry.click(startX: 50, startY: 14, endX: 52, endY: 15, capturing: false) == .record,
      "small jitter within the same recording target remains a click")
print("52 core checks passed")
