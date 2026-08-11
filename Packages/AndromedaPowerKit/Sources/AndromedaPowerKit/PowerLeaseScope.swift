import Foundation

/// Convenience helper for scoped async work.
///
/// Example:
/// try await withPowerLease(
///     manager: powerManager,
///     owner: "testflight-agent",
///     reason: "Archive and upload build",
///     requirements: [.preventSystemSleep]
/// ) {
///     try await uploadToTestFlight()
/// }
public func withPowerLease<T: Sendable>(
    manager: PowerAssertionManager,
    owner: String,
    reason: String,
    requirements: PowerRequirement,
    operation: @Sendable () async throws -> T
) async rethrows -> T {
    let lease = await manager.acquire(
        owner: owner,
        reason: reason,
        requirements: requirements
    )

    do {
        let value = try await operation()
        await manager.release(lease)
        return value
    } catch {
        await manager.release(lease)
        throw error
    }
}
