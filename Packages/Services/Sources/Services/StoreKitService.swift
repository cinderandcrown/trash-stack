// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation
#if canImport(Combine)
import Combine
#endif

#if canImport(StoreKit)
import StoreKit
#endif

/// StoreKit 2 IAP stubs. Product IDs match economy JSON / Configuration.storekit.
@MainActor
public final class StoreKitService: ObservableObject {
    public static let shared = StoreKitService()

    @Published public private(set) var productIdsLoaded: [String] = []
    @Published public private(set) var purchased: Set<String> = []

    public let stubProductIds = [
        "com.cinderandcrown.trashstack.gems40",
        "com.cinderandcrown.trashstack.gems210",
        "com.cinderandcrown.trashstack.gems450",
        "com.cinderandcrown.trashstack.gems1200",
        "com.cinderandcrown.trashstack.gems2500",
        "com.cinderandcrown.trashstack.starter",
        "com.cinderandcrown.trashstack.pass",
        "com.cinderandcrown.trashstack.pass25",
        "com.cinderandcrown.trashstack.removeads",
    ]

    public func loadProducts() async {
#if canImport(StoreKit)
        do {
            let products = try await Product.products(for: stubProductIds)
            productIdsLoaded = products.map(\.id)
        } catch {
            productIdsLoaded = []
        }
#else
        productIdsLoaded = stubProductIds
#endif
    }

    public func stubPurchase(productId: String) {
        purchased.insert(productId)
    }
}
