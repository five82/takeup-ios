import Testing
import UIKit
@testable import Takeup

@Suite(.serialized) @MainActor struct MPVControllerTests {
    @Test func metalSurfaceTracksLayoutWithoutImplicitAnimation() throws {
        let controller = MPVPlayerController()
        controller.loadViewIfNeeded()
        defer { controller.shutdown() }
        controller.view.bounds = CGRect(x: 0, y: 0, width: 640, height: 360)
        controller.view.layoutIfNeeded()
        let layer = try #require(controller.view.layer.sublayers?.first as? MetalLayer)
        #expect(layer.frame == controller.view.bounds)
        #expect(layer.drawableSize.width == 640 * layer.contentsScale)
        #expect(layer.drawableSize.height == 360 * layer.contentsScale)

        controller.view.bounds = CGRect(x: 0, y: 0, width: 360, height: 640)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        #expect(layer.frame == controller.view.bounds)
        #expect(layer.drawableSize.width == 360 * layer.contentsScale)
        #expect(layer.drawableSize.height == 640 * layer.contentsScale)
    }

    @Test func controlsAndBoostCanBeChangedAndShutdownWithoutMedia() {
        let controller = MPVPlayerController()
        controller.dialogueBoost = true
        controller.loadViewIfNeeded()
        controller.setDialogueBoost(false)
        #expect(!controller.dialogueBoost)
        controller.setPaused(true)
        controller.togglePause()
        controller.setCropToFill(true)
        controller.setAudioTrack(1)
        controller.setSubtitleTrack(nil)
        controller.shutdown()
        // Closing the player while an event is pending must leave controls inert.
        controller.setPaused(false)
        controller.setSubtitleTrack(2)
        controller.shutdown()
    }
}
