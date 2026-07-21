import AppKit
import SwiftUI

/// Remembers each document window's frame (keyed by the document's URL)
/// and puts the window back there whenever the document is opened.
///
/// macOS persists window frames through two stores that can disagree
/// after a crash or force quit: AppKit's window frame and SwiftUI's
/// scene state (snapshotted lazily). On the next open, the window is
/// created at SwiftUI's — possibly stale — frame, and SwiftUI applies
/// that same frame again when the deferred document content commits, so
/// the window visibly jumps once loading finishes. The app can't reach
/// either store, so this view keeps its own: it saves the frame on
/// every change and re-applies it as soon as the window exists, which
/// wins over both stores regardless of which one was stale.
///
/// While `active` (the document is still loading), the late re-apply is
/// recognized by its value: SwiftUI re-applies a frame it captured
/// earlier — the frame the window was born with, or the frame this view
/// set when it applied the remembered one. Only changes landing exactly
/// on one of those frames are snapped back; everything else — a user
/// drag or resize, wherever it happens in the event order — is
/// followed. This stays correct even when the main thread was blocked
/// and notifications arrive batched, where mouse-state heuristics
/// proved unreliable.
struct WindowFramePin: NSViewRepresentable {
  /// Pin against the stale re-apply while true; release once loading
  /// has settled.
  let active: Bool
  /// The document shown in the window; nil for a new, unsaved document,
  /// which then gets no frame memory.
  let documentURL: URL?

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSView {
    let view = PinView()
    view.coordinator = context.coordinator
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.active = active
    context.coordinator.documentURL = documentURL
    // The window can appear after makeNSView; keep trying until known.
    context.coordinator.attach(to: nsView.window)
    context.coordinator.adoptDocumentIfNeeded()
  }

  /// Attaches the coordinator as soon as the view lands in a window —
  /// synchronously, before the window is first drawn, so restoring the
  /// remembered frame doesn't flash the wrong position.
  final class PinView: NSView {
    weak var coordinator: Coordinator?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      coordinator?.attach(to: window)
      coordinator?.adoptDocumentIfNeeded()
    }
  }

  final class Coordinator {
    private static let defaultsKey = "documentWindowFrames"

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    /// Frames SwiftUI has seen and may re-apply late: the frame the
    /// window was born with and the remembered frame applied at adopt.
    /// A change landing exactly on one of these while loading is the
    /// stale re-apply, not the user.
    private var suspectFrames: [NSRect] = []
    /// The frame the window is held at while `active`, and the last
    /// frame written to the store once released.
    private var pinnedFrame: NSRect = .zero
    /// The store key derived from `documentURL`, once adopted. Also the
    /// marker that the remembered frame has been applied.
    private var documentKey: String?
    /// Reentrancy guards for the forced re-assert.
    private var forcing = false
    private var assertScheduled = false

    var active = true {
      didSet {
        // Releasing gets the final word: force-apply the pinned frame
        // even when the model already matches — SwiftUI's commit can
        // leave the on-screen frame different from `window.frame`.
        if oldValue, !active { forcePinnedFrame() }
      }
    }
    var documentURL: URL?

    func attach(to window: NSWindow?) {
      guard let window, self.window !== window else { return }
      self.window = window
      suspectFrames = [window.frame]
      pinnedFrame = window.frame
      removeObservers()
      for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
        observers.append(
          NotificationCenter.default.addObserver(
            forName: name, object: window, queue: .main
          ) { [weak self] _ in self?.handleFrameChange() })
      }
    }

    /// Once the window and the document it shows are both known, apply
    /// the frame remembered for it and start persisting frame changes.
    func adoptDocumentIfNeeded() {
      guard documentKey == nil, let window, let url = documentURL else { return }
      documentKey = url.absoluteString
      // Update `pinnedFrame` before setFrame: the frame-change handler
      // runs synchronously inside it and would otherwise snap the
      // window right back to the frame it was born with.
      if let saved = Self.savedFrames()[documentKey!].map(NSRectFromString),
        !saved.isEmpty, isOnSomeScreen(saved)
      {
        pinnedFrame = saved
        suspectFrames.append(saved)
        if saved != window.frame {
          window.setFrame(saved, display: true)
        }
      } else {
        pinnedFrame = window.frame
      }
      persist(pinnedFrame)
    }

    private func handleFrameChange() {
      guard !forcing, let window else { return }
      adoptDocumentIfNeeded()
      // Landing exactly on an already-seen frame while loading is
      // SwiftUI's stale re-apply — snap back now, and again once
      // SwiftUI's transaction is over: mid-commit, a synchronous revert
      // can silently lose to a later write that never posts a
      // notification.
      if active, suspectFrames.contains(window.frame), window.frame != pinnedFrame {
        window.setFrame(pinnedFrame, display: true)
        if !assertScheduled {
          assertScheduled = true
          DispatchQueue.main.async { [weak self] in
            self?.assertScheduled = false
            self?.forcePinnedFrame()
          }
        }
        return
      }
      // Anything else is a real move or resize — typically the user's.
      // Follow it so a drag during loading sticks.
      pinnedFrame = window.frame
      persist(window.frame)
    }

    /// Applies `pinnedFrame` in a way that reaches the window server
    /// even when `window.frame` already reports the right value: set a
    /// nudged frame first so the second call is never a no-op.
    private func forcePinnedFrame() {
      guard let window, !pinnedFrame.isEmpty, !forcing else { return }
      forcing = true
      defer { forcing = false }
      var nudged = pinnedFrame
      nudged.origin.y += 1
      window.setFrame(nudged, display: false)
      window.setFrame(pinnedFrame, display: true)
    }

    /// Save eagerly on every change so the remembered frame stays
    /// correct even when the app dies without a clean quit — the very
    /// case that makes the system's own stores disagree.
    private func persist(_ frame: NSRect) {
      guard let documentKey else { return }
      var frames = Self.savedFrames()
      frames[documentKey] = NSStringFromRect(frame)
      UserDefaults.standard.set(frames, forKey: Self.defaultsKey)
    }

    private static func savedFrames() -> [String: String] {
      UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    /// Guards against restoring onto a display that is no longer there.
    private func isOnSomeScreen(_ frame: NSRect) -> Bool {
      NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    private func removeObservers() {
      observers.forEach(NotificationCenter.default.removeObserver)
      observers.removeAll()
    }

    deinit { removeObservers() }
  }
}
