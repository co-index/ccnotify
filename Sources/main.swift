import AppKit
import Darwin
import UserNotifications

// ccnotify — clickable macOS notifications from the command line, built on
// UNUserNotificationCenter (the modern replacement for the API that
// terminal-notifier uses).
//
// Post mode:
//   ccnotify -message "..." [-title "..."] [-subtitle "..."]
//            [-sound Glass] [-activate com.microsoft.VSCode]
//
// Click mode: when the user clicks a notification after this process has
// exited, macOS relaunches the app with no arguments and delivers the
// response to the delegate, which activates the bundle id stored in the
// notification's userInfo.

let toolVersion =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

let usage = """
    ccnotify \(toolVersion) — clickable macOS notifications from the command line

    Usage:
      ccnotify -message <text> [-title <text>] [-subtitle <text>]
               [-sound <name>] [-image <path>] [-activate <bundle-id>]

    Options:
      -message   Notification body (required)
      -title     Notification title (default: ccnotify)
      -subtitle  Notification subtitle
      -sound     "default", a sound from /System/Library/Sounds (e.g. Glass,
                 Ping), or a custom sound file's name from ~/Library/Sounds
      -image     Image (png/jpg/gif) attached to the banner, shown as a
                 thumbnail on its right (the left app icon cannot change)
      -activate  Bundle id of the app to focus when the notification is clicked
      -help      Show this help
      -version   Print the version

    Clicking a notification relaunches ccnotify in the background, which then
    activates the app given with -activate.
    """

func value(after flag: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
        return nil
    }
    return args[index + 1]
}

let args = CommandLine.arguments
if args.contains("-help") || args.contains("--help") || args.contains("-h") {
    print(usage)
    exit(0)
}
if args.contains("-version") || args.contains("--version") {
    print("ccnotify \(toolVersion)")
    exit(0)
}

let message = value(after: "-message")
let titleArg = value(after: "-title") ?? "ccnotify"
let subtitleArg = value(after: "-subtitle")
let soundArg = value(after: "-sound")
let imageArg = value(after: "-image")
let activateArg = value(after: "-activate")

// A notification click relaunches the app with no arguments and no tty.
// A human typing `ccnotify` without -message gets the usage text instead
// of a process that silently waits.
if message == nil {
    if args.count > 1 || isatty(0) != 0 || isatty(1) != 0 {
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        exit(64)
    }
}

func exitSoon(_ seconds: Double) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
}

// The system moves attached files into its own store, so attach a copy to
// leave the caller's file untouched.
func makeAttachment(from path: String) -> UNNotificationAttachment? {
    let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard FileManager.default.fileExists(atPath: source.path) else {
        FileHandle.standardError.write(Data("ccnotify: image not found: \(path)\n".utf8))
        return nil
    }
    let copy = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(source.pathExtension)
    do {
        try FileManager.default.copyItem(at: source, to: copy)
        return try UNNotificationAttachment(identifier: "image", url: copy)
    } catch {
        FileHandle.standardError.write(
            Data("ccnotify: cannot attach image: \(error.localizedDescription)\n".utf8))
        return nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let body = message {
            post(body: body)
        } else {
            // Launched by a notification click; wait for didReceive below.
            exitSoon(5)
        }
    }

    private func post(body: String) {
        // Re-register this bundle with LaunchServices on every post. Brew
        // upgrades move the app to a new versioned Cellar path; without
        // this, a click can resolve the bundle id to a stale, deleted copy
        // and silently fail to relaunch the app.
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            let content = UNMutableNotificationContent()
            content.title = titleArg
            if let subtitle = subtitleArg {
                content.subtitle = subtitle
            }
            content.body = body
            if let sound = soundArg {
                content.sound =
                    sound == "default"
                    ? .default
                    : UNNotificationSound(named: UNNotificationSoundName(sound))
            }
            if let imagePath = imageArg, let attachment = makeAttachment(from: imagePath) {
                content.attachments = [attachment]
            }
            if let bundleID = activateArg {
                content.userInfo["activate"] = bundleID
            }
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request) { _ in
                // Give the notification a moment to hand off before exiting.
                exitSoon(0.3)
            }
        }
        // Safety net in case authorization never calls back.
        exitSoon(10)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo
        guard let bundleID = userInfo["activate"] as? String,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            exitSoon(0.2)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { exit(0) }
        }
        exitSoon(5)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) ->
            Void
    ) {
        completionHandler([.banner, .sound])
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// The delegate must be in place before the app finishes launching so click
// relaunches deliver their notification response.
UNUserNotificationCenter.current().delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
