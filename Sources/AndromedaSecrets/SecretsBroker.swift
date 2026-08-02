import AndromedaDomain
import Foundation

/// Stub lease response for future brokered execution and secret capability work.
public struct SecretLeaseReceipt: Sendable, Equatable {
    public let leaseID: LeaseID
    public let granted: Bool

    public init(leaseID: LeaseID, granted: Bool) {
        self.leaseID = leaseID
        self.granted = granted
    }
}

/// Placeholder broker surface to keep the package layout stable without shipping secret handling yet.
public actor SecretsBroker {
    public init() {}

    public func authorize(leaseID: LeaseID) -> SecretLeaseReceipt {
        SecretLeaseReceipt(leaseID: leaseID, granted: false)
    }
}
