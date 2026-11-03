import AppKit
import SwiftUI

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.workActive else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Cancel remaining work and quit?"
        alert.informativeText = "The current file operation must finish safely. Remaining scanning or Trash operations will be cancelled."
        alert.addButton(withTitle:"Cancel Work and Quit"); alert.addButton(withTitle:"Keep Working")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        model.cancelScan(); model.cancelRemoval()
        Task {
            while model.workActive { try? await Task.sleep(for:.milliseconds(100)) }
            sender.reply(toApplicationShouldTerminate:true)
        }
        return .terminateLater
    }
}
