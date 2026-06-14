import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage("anthropic_api_key") private var apiKey = ""
    @AppStorage("reminder_enabled") private var reminderEnabled = false
    @AppStorage("reminder_hour") private var reminderHour = 20
    @State private var notificationDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Anthropic API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("AI")
                } footer: {
                    Text("Required for AI summaries and structured logging. Your check-in text is sent to the AI; transcription itself happens on-device. Without a key, check-ins are still saved as plain journal entries. ⚠️ Demo only: in production this key lives on a backend, never in the app.")
                }

                Section {
                    Toggle("Daily check-in reminder", isOn: $reminderEnabled)
                        .onChange(of: reminderEnabled) { _, enabled in
                            Task { await updateReminder(enabled: enabled) }
                        }
                    if reminderEnabled {
                        Picker("Time", selection: $reminderHour) {
                            ForEach(6..<24, id: \.self) { h in
                                Text("\(h):00").tag(h)
                            }
                        }
                        .onChange(of: reminderHour) { _, _ in
                            Task { await updateReminder(enabled: true) }
                        }
                    }
                    if notificationDenied {
                        Text("Notifications are off in iOS Settings. Enable them to get reminders.")
                            .font(.footnote)
                            .foregroundStyle(DS.Colors.warning)
                    }
                } header: {
                    Text("Reminders")
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    Text("This app is a journaling tool, not a medical device. It never provides diagnoses. Always consult your doctor about your health.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func updateReminder(enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily_checkin"])
        guard enabled else { return }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else {
            notificationDenied = true
            reminderEnabled = false
            return
        }
        notificationDenied = false

        let content = UNMutableNotificationContent()
        content.title = "How was your day?"
        content.body = "A one-minute check-in keeps your health story complete."
        content.sound = .default

        var components = DateComponents()
        components.hour = reminderHour
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: "daily_checkin", content: content, trigger: trigger))
    }
}
