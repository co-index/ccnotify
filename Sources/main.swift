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
      -doctor    Diagnose the setup: registered copies, click routing,
                 notification permission
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

// lsregister is Apple's LaunchServices maintenance tool; it has lived at this
// path for many macOS releases and is the only way to remove a registration.
let lsregisterPath =
    "/System/Library/Frameworks/CoreServices.framework/Versions/A/"
    + "Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

func runDoctor() -> Never {
    var problems = 0
    print("ccnotify \(toolVersion) doctor")
    print("")

    guard let bundleID = Bundle.main.bundleIdentifier else {
        print("error: not running from an app bundle, so notifications cannot work.")
        print("Install via Homebrew instead: brew install co-index/tap/ccnotify")
        exit(1)
    }
    let selfURL = Bundle.main.bundleURL.standardizedFileURL
    print("  bundle id:    \(bundleID)")
    print("  this copy:    \(selfURL.path)")

    // Healing step: after a brew upgrade LaunchServices can still point at
    // the deleted old keg; re-registering makes this copy authoritative.
    LSRegisterURL(selfURL as CFURL, true)
    print("  registered:   this copy re-registered with LaunchServices")
    print("")

    // Where a notification click would route right now.
    if let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        let resolvedPath = resolved.standardizedFileURL.path
        if resolvedPath == selfURL.path {
            print("  click target: this copy ✓")
        } else {
            problems += 1
            print("  click target: \(resolvedPath)")
            print("                WARNING: clicks route to a different copy. Remove it")
            print("                (see below) or post one notification from this copy")
            print("                to take routing over.")
        }
    } else {
        problems += 1
        print("  click target: UNRESOLVED — LaunchServices cannot find \(bundleID)")
    }
    print("")

    print("  registered copies:")
    let copies = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
    if copies.isEmpty {
        print("    (none — LaunchServices returned no results)")
    }
    for url in copies {
        let path = url.standardizedFileURL.path
        if path == selfURL.path {
            print("    ok  \(path)  (this copy)")
            continue
        }
        problems += 1
        if !FileManager.default.fileExists(atPath: path) {
            print("    !!  \(path)")
            print("        gone from disk — stale registration. Clean up with:")
            print("        \(lsregisterPath) -u '\(path)'")
        } else if path.contains("/Cellar/ccnotify/") {
            print("    !!  \(path)")
            print("        old Homebrew keg. Clean up with: brew cleanup ccnotify")
        } else {
            print("    !!  \(path)")
            print("        extra copy — if it ever posts, it steals click routing.")
            print("        If it is not yours on purpose, remove it with:")
            print("        \(lsregisterPath) -u '\(path)'")
        }
    }
    print("")

    let semaphore = DispatchSemaphore(value: 0)
    var status = UNAuthorizationStatus.notDetermined
    var alert = UNNotificationSetting.notSupported
    UNUserNotificationCenter.current().getNotificationSettings { settings in
        status = settings.authorizationStatus
        alert = settings.alertSetting
        semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + 5) == .timedOut {
        problems += 1
        print("  permission:   check timed out — notification daemon not responding")
    } else {
        switch status {
        case .authorized, .provisional, .ephemeral:
            if alert == .enabled {
                print("  permission:   authorized — banners enabled")
            } else {
                problems += 1
                print("  permission:   authorized, but alerts are OFF —")
                print("                enable them under System Settings → Notifications → ccnotify")
            }
        case .denied:
            problems += 1
            print("  permission:   DENIED — allow ccnotify under System Settings → Notifications")
        case .notDetermined:
            print("  permission:   not requested yet — the first post will ask")
        @unknown default:
            print("  permission:   unknown status (\(status.rawValue))")
        }
    }

    print("")
    if problems == 0 {
        print("  no problems found.")
        exit(0)
    }
    print("  \(problems) potential issue(s) found — see above.")
    exit(1)
}

if args.contains("-doctor") {
    runDoctor()
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
        // openApplication(activates:) reports success but does not bring an
        // already-running app forward on macOS 14+ — cooperative activation
        // ignores the request from a background accessory app. Activating
        // the running process directly does work; if the app still is not
        // frontmost afterwards, /usr/bin/open performs a full LaunchServices
        // activation as a last resort.
        if let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        ).first {
            // .activateIgnoringOtherApps is documented as a no-op since
            // macOS 14, but empirically (macOS 26/27) activation only brings
            // the app forward when it is passed. Keep it despite the
            // deprecation warning; the open(1) fallback below covers any OS
            // where it stops working entirely.
            running.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
                    exit(0)
                }
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = ["-b", bundleID]
                try? task.run()
                task.waitUntilExit()
                exit(0)
            }
            exitSoon(6)
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
