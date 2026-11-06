import PianismCore
import SwiftUI

/// The Settings tab: connecting a piano (MIDI-2) and how it starts, pauses and saves a session (MIDI-1), when Practice
/// asks "Still practicing?" and stops a session (SES-3, SES-4), and the overlap warning (SES-5) for now; SET-1's other
/// settings join it one section at a time.
struct SettingsView: View {
    @Bindable var practice: PracticeModel

    @AppStorage(SettingsKey.showsOverlapWarning) private var showsOverlapWarning = true
    @AppStorage(SettingsKey.weeklyGoalDays) private var goalDays = WeeklyGoal.defaultDays
    @AppStorage(SettingsKey.dailyMinimum) private var dailyMinimum: TimeInterval = 0

    var body: some View {
        NavigationStack {
            Form {
                let pianos = practice.connectedPianos
                Section {
                    NavigationLink {
                        ConnectPianoView(pianos: pianos)
                    } label: {
                        if pianos.isEmpty {
                            Text("Connect a piano", bundle: .module)
                        } else {
                            Text("\(pianos.formatted(.list(type: .and))) connected", bundle: .module)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsPianos)
                    Picker(selection: $practice.startNotes) {
                        ForEach(1...10, id: \.self) { Text($0, format: .number).tag($0) }
                    } label: {
                        Text("Notes that start a session", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsStartNotes)
                    Picker(selection: $practice.pauseAfter) {
                        times(practice.pauseChoices)
                    } label: {
                        Text("Pause after a silence of", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsPauseAfter)
                    Picker(selection: $practice.saveAfter) {
                        times(practice.saveChoices)
                    } label: {
                        Text("Save after a silence of", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsSaveAfter)
                } header: {
                    Text("Piano", bundle: .module)
                } footer: {
                    Text("Pianism hears your piano while it's open on screen.", bundle: .module)
                }
                Section {
                    Picker(selection: $practice.nudge) {
                        times(practice.nudgeChoices)
                    } label: {
                        Text("Ask “Still practicing?” after", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsNudge)
                    Toggle(isOn: $practice.notifiesWhenAway) {
                        Text("Notify me when I'm away", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsNotifications)
                    #if os(iOS)
                        if practice.notificationPermission == .denied,
                            let settings = URL(string: UIApplication.openNotificationSettingsURLString)
                        {
                            Link(destination: settings) {
                                Text("Open the Settings app", bundle: .module)
                            }
                            .accessibilityIdentifier(AccessibilityID.settingsOpenNotificationSettings)
                        }
                    #endif
                    Picker(selection: $practice.cap) {
                        times(practice.capChoices)
                    } label: {
                        Text("Stop a session left running after", bundle: .module)
                    }
                    .disabled(!practice.canChangeCap)
                    .accessibilityIdentifier(AccessibilityID.settingsCap)
                } header: {
                    Text("Practice", bundle: .module)
                } footer: {
                    VStack(alignment: .leading) {
                        if practice.notificationPermission == .denied {
                            Text("Notifications are off for Pianism in the Settings app.", bundle: .module)
                        } else {
                            Text(
                                "Asks “Still practicing?” with a notification when Pianism isn't open.",
                                bundle: .module)
                        }
                        if !practice.canChangeCap {
                            Text("You can change when a session stops once this one ends.", bundle: .module)
                        }
                    }
                }
                Section {
                    Picker(selection: $goalDays) {
                        ForEach(WeeklyGoal.dayChoices, id: \.self) { days in
                            Text("^[\(days) day](inflect: true)", bundle: .module).tag(days)
                        }
                    } label: {
                        Text("Days a week", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsGoalDays)
                    Picker(selection: $dailyMinimum) {
                        Text("Any amount", bundle: .module).tag(TimeInterval(0))
                        times(WeeklyGoal.minimumChoices.filter { $0 > 0 })
                    } label: {
                        Text("A day counts after", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsDailyMinimum)
                } header: {
                    Text("Weekly goal", bundle: .module)
                } footer: {
                    Text("History shows how many weeks met this in the past year.", bundle: .module)
                }
                Section {
                    Toggle(isOn: $practice.remindsDaily) {
                        Text("Daily reminder", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsDailyReminder)
                    if practice.remindsDaily {
                        DatePicker(selection: $practice.dailyReminderTime, displayedComponents: .hourAndMinute) {
                            Text("Time", bundle: .module)
                        }
                        .accessibilityIdentifier(AccessibilityID.settingsDailyReminderTime)
                    }
                } header: {
                    Text("Reminder", bundle: .module)
                } footer: {
                    Text("Reminds you on days you haven't practiced yet.", bundle: .module)
                }
                Section {
                    Toggle(isOn: $showsOverlapWarning) {
                        Text("Overlap warning", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsOverlapWarning)
                } header: {
                    Text("History", bundle: .module)
                } footer: {
                    Text(
                        "Warns when a session you add or edit shares practice time with another. The day's total counts that time twice.",
                        bundle: .module)
                }
            }
            .navigationTitle(Text("Settings", bundle: .module))
        }
    }

    private func times(_ choices: [TimeInterval]) -> some View {
        ForEach(choices, id: \.self) { Text(ElapsedTime.spoken($0)).tag($0) }
    }
}

#Preview("No piano") {
    SettingsView(practice: .preview(.ready))
}

#Preview("Daily reminder on") {
    let practice = PracticeModel.preview(.ready, notifications: .allowed)
    practice.remindsDaily = true
    return SettingsView(practice: practice)
}

#Preview("Notifications off in the Settings app") {
    SettingsView(practice: .preview(.ready, notifications: .denied))
}

#Preview("Notifications off in the Settings app, dark, AX5") {
    SettingsView(practice: .preview(.running, notifications: .denied))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("A session running, a piano, dark, AX5") {
    let practice = PracticeModel.preview(.running)
    practice.connectedPianos = ["MIDI KEYBOARD"]
    return SettingsView(practice: practice)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
