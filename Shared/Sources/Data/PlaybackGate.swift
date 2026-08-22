import CoreMedia
import VideoToolbox

/// Playback capability gate for the TV app. The Apple TV 4K's A15 has no AV1
/// hardware decoder; 1080p AV1 holds up in dav1d software decode, but 4K does
/// not, so 4K AV1 titles refuse to play rather than stutter. The check is a
/// live VideoToolbox query, not a device-model list, so the block lifts itself
/// on AV1-capable hardware (and never fires on the M4 iPad).
enum PlaybackGate {
    static var hasAV1HardwareDecode: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    }

    /// Why this media cannot play on this device, or nil when it can.
    static func blockReason(for media: MediaFile?) -> String? {
        guard let video = media?.streams?.first(where: { $0.kind == "video" }) else { return nil }
        return blockReason(
            codec: video.codec,
            width: video.width,
            height: video.height,
            av1HardwareDecode: hasAV1HardwareDecode
        )
    }

    /// The decision itself, with the hardware capability passed in so tests
    /// can exercise both sides of it.
    static func blockReason(codec: String?, width: Int?, height: Int?, av1HardwareDecode: Bool) -> String? {
        guard codec?.lowercased() == "av1", !av1HardwareDecode else { return nil }
        // Anything beyond 1080p is past what software decode sustains.
        guard (width ?? 0) > 1920 || (height ?? 0) > 1080 else { return nil }
        return "This Apple TV can not play 4K AV1 video smoothly."
    }
}
