# OpenTelemetry

## Bootstrap

```swift
import OpenTelemetryApi
import OpenTelemetrySdk

func bootstrap(serviceName: String) {
    let exporter = StdoutSpanExporter()  // dev
    // OtlpTraceExporter(endpoint:) — prod
    let processor = SimpleSpanProcessor(spanExporter: exporter)
    OpenTelemetry.registerTracerProvider(
        tracerProvider: TracerProviderBuilder()
            .add(spanProcessor: processor)
            .with(resource: Resource(attributes: ["service.name": .string(serviceName)]))
            .build()
    )
}
```

## Spans

```swift
let span = tracer.spanBuilder(spanName: "operation").startSpan()
defer { span.end() }
span.setAttribute(key: "key", value: "value")
span.recordException(error)
```

## Metrics

```swift
let histogram = meter.histogram(name: "operation.duration")
histogram.record(ms, attributes: [:])
```

## Logging correlation

Append `trace_id` to log lines when span active.

## Privacy

No PII in attributes. Truncate errors.

## Domain span names

Anima operation names → **anima-swift** `anima-telemetry.md`. SDK setup → here.
