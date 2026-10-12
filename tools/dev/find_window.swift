// Print the CoreGraphics window id of the game window, for screencapture -l.
import CoreGraphics
let list = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
for w in list {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  let name = w[kCGWindowName as String] as? String ?? ""
  let num = w[kCGWindowNumber as String] as? Int ?? -1
  let on = w[kCGWindowIsOnscreen as String] as? Bool ?? false
  let alpha = w[kCGWindowAlpha as String] as? Double ?? -1
  let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
  if owner == "wine" && name == "Minecraft" {
    print("id=\(num) onscreen=\(on) alpha=\(alpha) bounds=\(b)")
  }
}
