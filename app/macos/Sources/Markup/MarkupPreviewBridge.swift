import WebKit

@MainActor enum MarkupPreviewBridge {
    static let world = WKContentWorld.world(name: "HyCode.MarkupPreview")
    static let name = "hycodePreviewScroll"
    // Only this fixed application script runs, in an isolated world. Content JS
    // stays disabled. Source text is never interpolated into JavaScript.
    static let script = """
        (() => {
          let pausedUntil = 0, pending = false, enabled = true, token = '';
          const clamp = n => Number.isFinite(n) ? Math.max(0, Math.min(1, n)) : 0;
          const range = () => Math.max(0, document.documentElement.scrollHeight - innerHeight);
          globalThis.hycodePreviewConfigure = (value, active) => { token = value; enabled = active; };
          globalThis.hycodePreviewScroll = (line, fraction, markdown) => {
            pausedUntil = performance.now() + 300;
            let target = null;
            if (markdown) {
              const markers = Array.from(document.querySelectorAll('[data-hycode-line]')).slice(0,8192);
              for (const item of markers) {
                const n = Number(item.dataset.hycodeLine);
                if (Number.isInteger(n) && n <= line) target = item;
              }
            }
            if (target) scrollTo(0, scrollY + target.getBoundingClientRect().top);
            else scrollTo(0, clamp(fraction) * range());
          };
          addEventListener('scroll', () => {
            if (pending || !enabled || !token || performance.now() < pausedUntil) return;
            pending = true;
            requestAnimationFrame(() => {
              pending = false;
              let line = null;
              for (const item of Array.from(document.querySelectorAll('[data-hycode-line]')).slice(0,8192)) {
                const n = Number(item.dataset.hycodeLine);
                if (Number.isInteger(n) && item.getBoundingClientRect().top <= 24) line = n;
              }
              webkit.messageHandlers.hycodePreviewScroll.postMessage({ token, line, fraction: clamp(scrollY / Math.max(1,range())) });
            });
          }, {passive: true});
        })();
        """
}
/// WKUserContentController retains handlers; the weak relay breaks the owner /
/// web view cycle even when a load is stopped before navigation completion.
@MainActor final class MarkupMessageRelay: NSObject, WKScriptMessageHandler {
    weak var owner: MarkupPreviewController?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.received(message)
    }
}
