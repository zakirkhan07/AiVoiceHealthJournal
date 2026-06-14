import Foundation
import HealthKit

/// Reads passive signals (steps, sleep, resting HR) to enrich insights.
/// All reads are optional — the app works fully without HealthKit access.
@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    struct DailySignals: Identifiable {
        let id = UUID()
        let date: Date
        var steps: Double?
        var sleepHours: Double?
        var restingHR: Double?
    }

    @Published private(set) var authorized = false
    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.restingHeartRate),
            HKCategoryType(.sleepAnalysis)
        ]
    }

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorized = true
            AnalyticsLogger.shared.log(.healthKitConnected)
        } catch {
            authorized = false
        }
    }

    /// Last N days of signals, most recent first. Missing days return nils — UI shows "—".
    func recentSignals(days: Int = 7) async -> [DailySignals] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        var out: [DailySignals] = []
        let cal = Calendar.current
        for offset in 0..<days {
            let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -offset, to: .now)!)
            async let steps = sum(.stepCount, unit: .count(), day: day)
            async let hr = average(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), day: day)
            async let sleep = sleepHours(day: day)
            out.append(DailySignals(date: day, steps: await steps, sleepHours: await sleep, restingHR: await hr))
        }
        return out
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, day: Date) async -> Double? {
        await statistic(id: id, unit: unit, day: day, options: .cumulativeSum) { $0.sumQuantity() }
    }

    private func average(_ id: HKQuantityTypeIdentifier, unit: HKUnit, day: Date) async -> Double? {
        await statistic(id: id, unit: unit, day: day, options: .discreteAverage) { $0.averageQuantity() }
    }

    private func statistic(id: HKQuantityTypeIdentifier, unit: HKUnit, day: Date,
                           options: HKStatisticsOptions,
                           extract: @escaping (HKStatistics) -> HKQuantity?) async -> Double? {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let predicate = HKQuery.predicateForSamples(withStart: day, end: end)
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(id),
                                          quantitySamplePredicate: predicate,
                                          options: options) { _, stats, _ in
                let value = stats.flatMap(extract)?.doubleValue(for: unit)
                cont.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func sleepHours(day: Date) async -> Double? {
        // Sleep for "last night": from 6pm previous day to noon of `day`.
        let start = Calendar.current.date(byAdding: .hour, value: -6, to: day)!
        let end = Calendar.current.date(byAdding: .hour, value: 12, to: day)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis),
                                      predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    cont.resume(returning: nil); return
                }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                ]
                let seconds = samples
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: seconds > 0 ? seconds / 3600 : nil)
            }
            store.execute(query)
        }
    }
}
