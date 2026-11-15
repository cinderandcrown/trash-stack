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
        let params = RequestParameters()
        params.isTaggedForUnderAgeOfConsent = false
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: params)
        } catch {
            // Continue; non-personalized ads may still serve.
        }
        // Google Mobile Ads 11.x uses GADMobileAds; keep a single start path for CI.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            GADMobileAds.sharedInstance().start { _ in
                cont.resume()
            }
        }
        await AdsService.shared.bootstrap()
    }
}
