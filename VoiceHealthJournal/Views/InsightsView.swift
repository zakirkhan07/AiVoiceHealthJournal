import SwiftUI
import SwiftData
import Charts

/// Weekly insights: symptom frequency, mood trend, and passive HealthKit signals.
/// Insight copy is deliberately careful — correlations, never diagnoses.
struct InsightsView: View {
    @Query(sort: \JournalEntry.createdAt, order: .reverse) private var entries: [JournalEntry]
    @StateObject private var healthKit = HealthKitService.shared
    @State private var signals: [HealthKitService.DailySignals] = []

    private var lastWeek: [JournalEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        return entries.filter { $0.createdAt >= cutoff }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.m) {
                    if lastWeek.count < 2 {
                        DSCard {
                            Label("Keep going", systemImage: "sparkles")
                                .font(.headline)
                            Text("Insights unlock after a few check-ins. \(max(0, 2 - lastWeek.count)) more to go — patterns need data.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        moodChart
                        symptomFrequency
                    }
                    healthSignals
                }
                .padding()
            }
            .navigationTitle("Insights")
            .task {
                AnalyticsLogger.shared.log(.insightsViewed)
                if healthKit.authorized {
                    signals = await healthKit.recentSignals()
                }
            }
        }
    }

    // MARK: - Mood trend

    private var moodChart: some View {
        DSCard {
            Text("Mood this week").font(.headline)
            let points = lastWeek.compactMap { entry -> (Date, Int)? in
                guard let mood = entry.moodScore else { return nil }
                return (entry.createdAt, mood)
            }
            if points.isEmpty {
                Text("No mood data yet — mention how you're feeling in a check-in.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Chart(points, id: \.0) { date, mood in
                    LineMark(x: .value("Day", date, unit: .day), y: .value("Mood", mood))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(DS.Colors.accent)
                    PointMark(x: .value("Day", date, unit: .day), y: .value("Mood", mood))
                        .foregroundStyle(DS.Colors.accent)
                }
                .chartYScale(domain: 0...5)
                .frame(height: 160)
                .accessibilityLabel("Line chart of mood scores over the past week")
            }
        }
    }

    // MARK: - Symptom frequency

    private func symptomCounts() -> [(name: String, count: Int, avgSeverity: Double)] {
        let grouped = Dictionary(grouping: lastWeek.flatMap(\.symptoms), by: { $0.name.lowercased() })
        let mapped = grouped.map { key, values -> (name: String, count: Int, avgSeverity: Double) in
            let avg = Double(values.map(\.severity).reduce(0, +)) / Double(values.count)
            return (name: key, count: values.count, avgSeverity: avg)
        }
        return Array(mapped.sorted { $0.count > $1.count }.prefix(5))
    }

    private var symptomFrequency: some View {
        DSCard {
            Text("Most frequent symptoms").font(.headline)
            let counts = symptomCounts()

            if counts.isEmpty {
                Text("No symptoms logged this week — that's worth celebrating.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Chart(Array(counts), id: \.name) { item in
                    BarMark(x: .value("Days", item.count), y: .value("Symptom", item.name.capitalized))
                        .foregroundStyle(item.avgSeverity > 3 ? DS.Colors.danger : DS.Colors.accent)
                        .cornerRadius(4)
                }
                .frame(height: CGFloat(counts.count) * 40)
                .accessibilityLabel("Bar chart of symptom frequency")
                Text("Red bars average severity above 3/5.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - HealthKit

    private var healthSignals: some View {
        DSCard {
            HStack {
                Text("Passive signals").font(.headline)
                Spacer()
                if !healthKit.authorized {
                    Button("Connect Health") {
                        Task {
                            await healthKit.requestAccess()
                            signals = await healthKit.recentSignals()
                        }
                    }
                    .font(.footnote.bold())
                }
            }
            if !healthKit.authorized {
                Text("Connect Apple Health to see how sleep, steps, and heart rate line up with your symptoms.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if signals.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                ForEach(signals.prefix(7)) { day in
                    HStack {
                        Text(day.date, format: .dateTime.weekday(.abbreviated))
                            .font(.caption.bold())
                            .frame(width: 36, alignment: .leading)
                        signalCell("figure.walk", day.steps.map { "\(Int($0))" })
                        signalCell("bed.double", day.sleepHours.map { String(format: "%.1fh", $0) })
                        signalCell("heart", day.restingHR.map { "\(Int($0))" })
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func signalCell(_ icon: String, _ value: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(DS.Colors.accent)
            Text(value ?? "—").foregroundStyle(value == nil ? .secondary : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
