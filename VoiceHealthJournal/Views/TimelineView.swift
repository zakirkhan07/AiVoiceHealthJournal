import SwiftUI
import SwiftData

// MARK: - Timeline

struct TimelineView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \JournalEntry.createdAt, order: .reverse) private var entries: [JournalEntry]
    @State private var exportURL: URL?
    @State private var searchText = ""
    @State private var filterState: FilterState = .all
    @State private var deleteCandidate: JournalEntry?
    @State private var showDeleteConfirm = false

    enum FilterState: String, CaseIterable {
        case all = "All"
        case done = "Done"
        case failed = "Failed"
    }

    private var filtered: [JournalEntry] {
        entries.filter { entry in
            let matchesFilter: Bool = switch filterState {
            case .all: true
            case .done: entry.state == .done
            case .failed: entry.state == .failed
            }
            guard matchesFilter else { return false }
            if searchText.isEmpty { return true }
            let q = searchText.lowercased()
            return entry.transcript.lowercased().contains(q)
                || (entry.aiSummary?.lowercased().contains(q) ?? false)
                || entry.symptoms.contains { $0.name.lowercased().contains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No check-ins yet",
                        systemImage: "mic.circle",
                        description: Text("Your first check-in takes under a minute. Just talk about your day.")
                    )
                } else {
                    VStack(spacing: 0) {
                        filterPills
                        if filtered.isEmpty {
                            ContentUnavailableView.search(text: searchText.isEmpty ? filterState.rawValue : searchText)
                                .frame(maxHeight: .infinity)
                        } else {
                            List {
                                ForEach(filtered) { entry in
                                    NavigationLink(value: entry.id) {
                                        EntryRow(entry: entry)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteCandidate = entry
                                            showDeleteConfirm = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        if entry.state == .failed {
                                            Button {
                                                Task {
                                                    let vm = CheckInViewModel()
                                                    await vm.retry(entry: entry, context: context)
                                                }
                                            } label: {
                                                Label("Retry", systemImage: "arrow.clockwise")
                                            }
                                            .tint(DS.Colors.accent)
                                        }
                                    }
                                }
                            }
                            .listStyle(.insetGrouped)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search symptoms, transcripts…")
            .navigationTitle("Journal (\(entries.count))")
            .navigationDestination(for: UUID.self) { id in
                if let entry = entries.first(where: { $0.id == id }) {
                    EntryDetailView(entry: entry)
                }
            }
            .toolbar {
                if !entries.isEmpty {
                    Button {
                        exportURL = DoctorReportService.generatePDF(entries: filtered.isEmpty ? entries : filtered)
                    } label: {
                        Label("Doctor report", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(item: Binding(
                get: { exportURL.map { ShareItem(url: $0) } },
                set: { _ in exportURL = nil })
            ) { item in
                ShareSheet(url: item.url)
            }
            .confirmationDialog(
                "Delete this check-in?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let entry = deleteCandidate {
                        withAnimation { context.delete(entry) }
                        try? context.save()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterState.allCases, id: \.self) { state in
                    let count: Int = switch state {
                    case .all: entries.count
                    case .done: entries.filter { $0.state == .done }.count
                    case .failed: entries.filter { $0.state == .failed }.count
                    }
                    Button {
                        withAnimation(.spring(duration: 0.25)) { filterState = state }
                    } label: {
                        HStack(spacing: 4) {
                            Text(state.rawValue)
                            Text("\(count)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.white.opacity(0.25), in: Capsule())
                        }
                        .font(.subheadline.weight(filterState == state ? .semibold : .regular))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(filterState == state ? DS.Colors.accent : DS.Colors.accentSoft,
                                    in: Capsule())
                        .foregroundStyle(filterState == state ? .white : DS.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Entry Row

struct EntryRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.createdAt, style: .date)
                    .font(.subheadline.bold())
                Text(entry.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                stateBadge
            }
            Text(entry.aiSummary ?? entry.transcript)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !entry.symptoms.isEmpty {
                HStack(spacing: 6) {
                    ForEach(entry.symptoms.prefix(3)) { s in
                        Text(s.name)
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(DS.Colors.accentSoft, in: Capsule())
                    }
                    if entry.symptoms.count > 3 {
                        Text("+\(entry.symptoms.count - 3)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var stateBadge: some View {
        switch entry.state {
        case .processing:
            ProgressView().controlSize(.mini)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(DS.Colors.warning)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Processing failed — swipe right to retry")
        case .pending:
            Image(systemName: "clock").foregroundStyle(.secondary).font(.caption)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(DS.Colors.positive)
        }
    }
}

// MARK: - Detail

struct EntryDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: JournalEntry
    @StateObject private var viewModel = CheckInViewModel()
    @State private var showAddSymptom = false
    @State private var showAddLifestyle = false
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            if entry.state == .failed {
                StatusBanner(kind: .error,
                             message: entry.lastError ?? "Processing failed.") {
                    Task { await viewModel.retry(entry: entry, context: context) }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if let summary = entry.aiSummary {
                Section("Summary") {
                    Text(summary)
                    if let mood = entry.moodScore {
                        HStack {
                            Text("Mood")
                            Spacer()
                            SeverityDots(severity: mood)
                        }
                    }
                }
            }

            Section {
                if entry.symptoms.isEmpty {
                    Text("None recorded").foregroundStyle(.secondary)
                }
                ForEach(entry.symptoms) { symptom in
                    SymptomEditorRow(symptom: symptom)
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(entry.symptoms[i]) }
                    try? context.save()
                    AnalyticsLogger.shared.log(.logEdited, props: ["action": "delete_symptom"])
                }
                Button {
                    showAddSymptom = true
                } label: {
                    Label("Add symptom", systemImage: "plus.circle")
                        .foregroundStyle(DS.Colors.accent)
                }
            } header: {
                Text("Symptoms")
            }

            Section {
                if entry.lifestyle.isEmpty {
                    Text("None recorded").foregroundStyle(.secondary)
                }
                ForEach(entry.lifestyle) { item in
                    HStack {
                        Image(systemName: icon(for: item.category))
                            .foregroundStyle(DS.Colors.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.detail)
                            Text(item.category.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(entry.lifestyle[i]) }
                    try? context.save()
                }
                Button {
                    showAddLifestyle = true
                } label: {
                    Label("Add lifestyle note", systemImage: "plus.circle")
                        .foregroundStyle(DS.Colors.accent)
                }
            } header: {
                Text("Lifestyle")
            }

            Section("What you said") {
                Text(entry.transcript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete this check-in", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSymptom) {
            AddSymptomSheet { name, severity in
                let log = SymptomLog(name: name, severity: severity, userEdited: true)
                entry.symptoms.append(log)
                try? context.save()
                AnalyticsLogger.shared.log(.logEdited, props: ["action": "add_symptom"])
            }
        }
        .sheet(isPresented: $showAddLifestyle) {
            AddLifestyleSheet { category, detail in
                let log = LifestyleLog(category: category, detail: detail, userEdited: true)
                entry.lifestyle.append(log)
                try? context.save()
            }
        }
        .confirmationDialog(
            "Delete this check-in?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                context.delete(entry)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private func icon(for category: String) -> String {
        switch category {
        case "sleep": return "bed.double.fill"
        case "food": return "fork.knife"
        case "exercise": return "figure.run"
        case "stress": return "brain.head.profile"
        default: return "sparkles"
        }
    }
}

// MARK: - Add Symptom Sheet

struct AddSymptomSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (String, Int) -> Void

    @State private var name = ""
    @State private var severity = 3

    var body: some View {
        NavigationStack {
            Form {
                Section("Symptom name") {
                    TextField("e.g. headache, fatigue", text: $name)
                        .textInputAutocapitalization(.never)
                }
                Section {
                    HStack {
                        Text("Severity")
                        Spacer()
                        SeverityDots(severity: severity)
                    }
                    Slider(value: Binding(
                        get: { Double(severity) },
                        set: { severity = Int($0.rounded()) }
                    ), in: 1...5, step: 1)
                    .tint(DS.Colors.accent)
                }
            }
            .navigationTitle("Add Symptom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, severity)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Add Lifestyle Sheet

struct AddLifestyleSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (String, String) -> Void

    @State private var detail = ""
    @State private var category = "other"

    private let categories = ["sleep", "food", "exercise", "stress", "other"]

    private func icon(for cat: String) -> String {
        switch cat {
        case "sleep": return "bed.double.fill"
        case "food": return "fork.knife"
        case "exercise": return "figure.run"
        case "stress": return "brain.head.profile"
        default: return "sparkles"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { cat in
                            Label(cat.capitalized, systemImage: icon(for: cat)).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Detail") {
                    TextField("e.g. slept 7 hours, skipped breakfast", text: $detail)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .navigationTitle("Add Lifestyle Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = detail.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(category, trimmed)
                        dismiss()
                    }
                    .disabled(detail.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Symptom Editor Row

struct SymptomEditorRow: View {
    @Bindable var symptom: SymptomLog

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(symptom.name.capitalized).font(.body.weight(.medium))
                Spacer()
                SeverityDots(severity: symptom.severity)
            }
            Slider(value: Binding(
                get: { Double(symptom.severity) },
                set: {
                    symptom.severity = Int($0.rounded())
                    if !symptom.userEdited {
                        symptom.userEdited = true
                        AnalyticsLogger.shared.log(.logEdited, props: ["action": "severity_change"])
                    }
                }), in: 1...5, step: 1)
            .tint(DS.Colors.accent)
            if let note = symptom.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if symptom.userEdited {
                Text("Edited by you").font(.caption2).foregroundStyle(DS.Colors.positive)
            }
        }
        .padding(.vertical, 2)
    }
}
