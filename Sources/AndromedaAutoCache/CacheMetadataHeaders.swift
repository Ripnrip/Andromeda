import Foundation

/// Response header names and values matching montevive/autocache.
public enum AutocacheHeader {
    public static let injected = "X-Autocache-Injected"
    public static let totalTokens = "X-Autocache-Total-Tokens"
    public static let cachedTokens = "X-Autocache-Cached-Tokens"
    public static let cacheRatio = "X-Autocache-Cache-Ratio"
    public static let strategy = "X-Autocache-Strategy"
    public static let model = "X-Autocache-Model"
    public static let roiFirstCost = "X-Autocache-ROI-FirstCost"
    public static let roiSavings = "X-Autocache-ROI-Savings"
    public static let roiBreakEven = "X-Autocache-ROI-BreakEven"
    public static let roiPercent = "X-Autocache-ROI-Percent"
    public static let breakpoints = "X-Autocache-Breakpoints"
    public static let savings10 = "X-Autocache-Savings-10req"
    public static let savings100 = "X-Autocache-Savings-100req"
    public static let bypass = "X-Autocache-Bypass"
    public static let disable = "X-Autocache-Disable"
}

public enum CacheMetadataHeaders {
    /// Builds Autocache analytics headers for an HTTP response.
    public static func make(from metadata: CacheMetadata) -> [(name: String, value: String)] {
        var headers: [(String, String)] = [
            (AutocacheHeader.injected, metadata.cacheInjected ? "true" : "false"),
            (AutocacheHeader.totalTokens, String(metadata.totalTokens)),
            (AutocacheHeader.cachedTokens, String(metadata.cachedTokens)),
            (AutocacheHeader.cacheRatio, String(format: "%.3f", metadata.cacheRatio)),
            (AutocacheHeader.strategy, metadata.strategy),
            (AutocacheHeader.model, metadata.model),
            (AutocacheHeader.roiFirstCost, PricingCalculator.formatCost(metadata.roi.firstRequestCost)),
            (AutocacheHeader.roiSavings, PricingCalculator.formatCost(metadata.roi.subsequentSavings)),
            (AutocacheHeader.roiBreakEven, String(metadata.roi.breakEvenRequests)),
            (AutocacheHeader.roiPercent, String(format: "%.1f", metadata.roi.percentSavings)),
            (AutocacheHeader.savings10, PricingCalculator.formatCost(metadata.roi.savingsAt10Requests)),
            (AutocacheHeader.savings100, PricingCalculator.formatCost(metadata.roi.savingsAt100Requests)),
        ]
        if !metadata.breakpoints.isEmpty {
            headers.append((AutocacheHeader.breakpoints, metadata.breakpointsHeader))
        }
        return headers
    }

    public static func shouldBypass(headers: [(name: String, value: String)]) -> Bool {
        for (name, value) in headers {
            let lower = name.lowercased()
            if lower == AutocacheHeader.bypass.lowercased()
                || lower == AutocacheHeader.disable.lowercased()
            {
                let normalized = value.lowercased()
                if normalized == "true" || normalized == "1" { return true }
            }
        }
        return false
    }
}
