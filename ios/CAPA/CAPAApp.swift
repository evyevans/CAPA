import SwiftUI
import UserNotifications

@main
struct CAPAApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, audio: model.audio, ptt: model.ptt)
                .preferredColorScheme(.dark)
                .task { await model.initialize() }
                .onOpenURL { url in
                    guard url.scheme == "capavoice", url.host == "record" else { return }
                    Task { await model.toggleRecording() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.refresh(); await model.syncDevice() }
                    } else if phase == .background, model.audio.recording, !model.ptt.joined {
                        model.interruptAudio()
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Initialize before any view appears: an incoming PTT push may cold-launch the process.
        Task { @MainActor in await AppModel.shared.initialize() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in AppModel.shared.registerNotificationToken(deviceToken) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in AppModel.shared.message = "Push registration failed. Results remain available when you open CAPA." }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["event_id"] as? String,
           UUID(uuidString: id) != nil {
            Task { @MainActor in await AppModel.shared.openUpdate(id) }
        }
        completionHandler()
    }
}
