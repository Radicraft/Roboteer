import AppKit
import WebKit
// usage: snap in.html out.png width height
let a = CommandLine.arguments
let inURL = URL(fileURLWithPath: a[1]); let out = a[2]
let w = CGFloat(Double(a[3])!), h = CGFloat(Double(a[4])!)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
class D: NSObject, WKNavigationDelegate {
  var view: WKWebView!
  func webView(_ v: WKWebView, didFinish n: WKNavigation!) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
      let c = WKSnapshotConfiguration(); c.rect = CGRect(x: 0, y: 0, width: w, height: h); c.snapshotWidth = NSNumber(value: Double(w))
      v.takeSnapshot(with: c) { img, err in
        guard let img = img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("fail", err as Any); exit(1) }
        try! png.write(to: URL(fileURLWithPath: out)); exit(0)
      }
    }
  }
}
let d = D()
let win = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
let v = WKWebView(frame: NSRect(x: 0, y: 0, width: w, height: h))
v.navigationDelegate = d; d.view = v
win.contentView = v
v.loadFileURL(inURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { print("timeout"); exit(2) }
app.run()
