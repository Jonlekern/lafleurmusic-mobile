import Flutter
import UIKit
import UniformTypeIdentifiers

/// Canal `studio.lafleur/device` : dossier des copies, sélecteur de dossier, place libre.
final class DeviceChannel: NSObject, UIDocumentPickerDelegate {
  private let channel: FlutterMethodChannel
  private var pending: FlutterResult?
  private var accessed: URL?  // dossier en service, accès gardé ouvert
  private var candidate: URL?  // dossier choisi mais pas encore adopté, accès ouvert aussi

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "studio.lafleur/device", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "defaultRoot":
      do {
        let docs = try FileManager.default.url(
          for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("LAFLEURMUSIC", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        result(dir.path)
      } catch {
        result(FlutterError(code: "default_root", message: nil, details: nil))
      }
    case "privateRoot":
      // dossier privé des morceaux gardés : parti avec l'appli, jamais dans la sauvegarde iCloud
      // (la musique se re-télécharge) ; l'exclusion est remise à chaque appel, elle ne coûte rien
      do {
        let support = try FileManager.default.url(
          for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var dir = support.appendingPathComponent("LAFLEURMUSIC", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if args?["excludeFromBackup"] as? Bool ?? true {
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try dir.setResourceValues(values)
        }
        result(dir.path)
      } catch {
        result(FlutterError(code: "private_root", message: nil, details: nil))
      }
    case "pickFolder":
      pickFolder(result)
    case "commitFolder":
      // le candidat devient le dossier en service ; l'ancien accès est fermé
      if let c = candidate {
        stopAccess()
        accessed = c
        candidate = nil
      }
      result(nil)
    case "releaseCandidate":
      stopCandidate()
      result(nil)
    case "openBookmark":
      guard let b64 = args?["bookmark"] as? String, let data = Data(base64Encoded: b64) else {
        result(FlutterError(code: "bookmark", message: nil, details: nil))
        return
      }
      openBookmark(data, result)
    case "freeBytes":
      guard let path = args?["path"] as? String else {
        result(FlutterError(code: "args", message: nil, details: nil))
        return
      }
      let url = URL(fileURLWithPath: path)
      let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      result(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    case "announce":
      result(nil)  // rien à faire sur iOS
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openBookmark(_ data: Data, _ result: FlutterResult) {
    var stale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    else {
      result(FlutterError(code: "bookmark", message: nil, details: nil))
      return
    }
    guard url.startAccessingSecurityScopedResource() else {
      result(FlutterError(code: "access", message: nil, details: nil))
      return
    }
    stopAccess()
    accessed = url
    var out: [String: Any] = ["path": url.path]
    if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
      out["bookmark"] = fresh.base64EncodedString()
    }
    result(out)
  }

  private func stopCandidate() {
    candidate?.stopAccessingSecurityScopedResource()
    candidate = nil
  }

  private func stopAccess() {
    accessed?.stopAccessingSecurityScopedResource()
    accessed = nil
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  private func pickFolder(_ result: @escaping FlutterResult) {
    guard pending == nil, let presenter = topViewController() else {
      result(FlutterError(code: "busy", message: nil, details: nil))
      return
    }
    pending = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let result = pending
    pending = nil
    guard let url = urls.first, url.startAccessingSecurityScopedResource() else {
      result?(FlutterError(code: "access", message: nil, details: nil))
      return
    }
    do {
      let data = try url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      stopCandidate()  // un choix précédent jamais adopté
      candidate = url  // le dossier en service garde son accès jusqu'à commitFolder
      result?(["path": url.path, "bookmark": data.base64EncodedString()])
    } catch {
      url.stopAccessingSecurityScopedResource()
      result?(FlutterError(code: "bookmark", message: nil, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pending
    pending = nil
    result?(nil)
  }
}
