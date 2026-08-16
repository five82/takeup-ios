import UIKit

/// CAMetalLayer with two MoltenVK workarounds, taken from the MPVKit demo:
/// - MoltenVK forces drawableSize to 1x1 to complete presentation, which
///   flickers and can stick (mpv-player/mpv#13651).
/// - wantsExtendedDynamicRangeContent only activates EDR from the main thread.
final class MetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }

    override var wantsExtendedDynamicRangeContent: Bool {
        get { super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                DispatchQueue.main.sync {
                    super.wantsExtendedDynamicRangeContent = newValue
                }
            }
        }
    }
}
