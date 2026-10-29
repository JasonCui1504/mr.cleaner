import SwiftUI
import Quartz

/// Quick Look preview of the selected file: the same read-only viewer Finder
/// uses for Space-bar previews. This is the only place in the app that causes
/// a file's contents to be read, and only for the one file you select.
/// Cloud-only files are never previewed, so nothing is downloaded.
struct FilePreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view: QLPreviewView = QLPreviewView(frame: .zero, style: .normal)
        view.autostarts = true
        view.shouldCloseWithWindow = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        // Runs when the selection changes (e.g. to several rows). Drop the item
        // first so a preview still loading is cancelled before the view closes.
        view.previewItem = nil
        view.close()
    }
}
