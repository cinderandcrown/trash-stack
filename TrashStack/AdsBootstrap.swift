// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation
import AppTrackingTransparency
import UserMessagingPlatform
import GoogleMobileAds
import Services

/// Wires Google Mobile Ads (test IDs), UMP, and ATT.
enum AdsBootstrap {
    @MainActor
    static func start() async {
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            await ATTrackingManager.requestTrackingAuthorization()
        }
        await requestUMPConsent()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            GADMobileAds.sharedInstance().start { _ in
                cont.resume()
            }
        }
        await AdsService.shared.bootstrap()
    }

    /// UMP 2.x SPM binary still exposes the ObjC-prefixed API surface.
    @MainActor
    private static func requestUMPConsent() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let params = UMPRequestParameters()
            // ObjC property name (Swift `isTagged…` rename is not on this SPM binary).
            params.tagForUnderAgeOfConsent = false
            UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: params) { _ in
                // Form presentation is skipped in CI / simulator smoke; non-personalized ads may still serve.
                cont.resume()
            }
        }
    }
}
