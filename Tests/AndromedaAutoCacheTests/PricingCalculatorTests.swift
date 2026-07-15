import Testing
@testable import AndromedaAutoCache

@Suite("PricingCalculator")
struct PricingCalculatorTests {
    let pricing = PricingCalculator()

    @Test("cache read is 10% of base input for sonnet")
    func cacheReadDiscount() {
        let model = "claude-3-5-sonnet-20241022"
        let base = pricing.baseCost(model: model, inputTokens: 1_000_000)
        let read = pricing.cacheReadCost(model: model, tokens: 1_000_000)
        #expect(abs(base - 3.0) < 0.0001)
        #expect(abs(read - 0.30) < 0.0001)
    }

    @Test("breakpoint ROI break-even is positive for cacheable content")
    func breakpointBreakEven() {
        let estimate = pricing.estimateBreakpointROI(
            model: "claude-3-5-sonnet-20241022",
            tokens: 2048,
            ttl: "5m"
        )
        #expect(estimate.writeCost > 0)
        #expect(estimate.readSavings > 0)
        #expect(estimate.breakEven >= 1)
    }

    @Test("formatCost uses finer precision for tiny amounts")
    func formatCost() {
        #expect(PricingCalculator.formatCost(0.000012) == "$0.000012")
        #expect(PricingCalculator.formatCost(0.0045) == "$0.0045")
        #expect(PricingCalculator.formatCost(0.125) == "$0.125")
        #expect(PricingCalculator.formatCost(1.5) == "$1.50")
    }
}
