import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsManager
    @Environment(\.dismiss) var dismiss
    @State private var testDataMessage = ""
    @State private var showTestDataFailureAlert = false

    var healthManager: HealthKitManager = .shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto-dismiss save confirmation", isOn: $settings.autoDismissSaveConfirmation)
                        .accessibilityIdentifier("autoDismissSaveConfirmationToggle")
                } header: {
                    Text("Export Behavior")
                } footer: {
                    Text("Closes the save confirmation after 5 seconds.")
                }

                Section {
                    Picker("Date Format", selection: $settings.dateFormat) {
                        ForEach(DateFormatOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .accessibilityIdentifier("dateFormatPicker")
                    Picker("Sort Order", selection: $settings.sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .accessibilityIdentifier("sortOrderPicker")
                } header: {
                    Text("Export Format")
                }

                Section {
                    Picker("Temperature", selection: $settings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .accessibilityIdentifier("temperaturePicker")

                    Picker("Weight", selection: $settings.weightUnit) {
                        ForEach(WeightUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .accessibilityIdentifier("weightUnitPicker")
                } header: {
                    Text("Units")
                }

                #if targetEnvironment(simulator)
                Section {
                    Button("Generate Weight Data", action: generateTestData)

                    if !testDataMessage.isEmpty {
                        Text(testDataMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Testing")
                }
                #endif

                Section {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Text("Privacy Policy & Disclaimer")
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .fontDesign(.rounded)
            .tint(Color("AccentColor"))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) {
                        dismiss()
                    }
                    .accessibilityIdentifier("doneButton")
                }
            }
            #if targetEnvironment(simulator)
            .alert("Failed to Generate Weight Data", isPresented: $showTestDataFailureAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(testDataMessage.replacingOccurrences(of: "✗ ", with: ""))
            }
            #endif
        }
    }

    #if targetEnvironment(simulator)
    private func generateTestData() {
        Task {
            do {
                try await healthManager.generateTestData()
                testDataMessage = "✓ Weight data generated (60 days)"
            } catch {
                testDataMessage = "✗ \(HealthKitQueryHelpers.simulatorTestDataFailureMessage(error))"
                showTestDataFailureAlert = true
            }
        }
    }
    #endif
}

#Preview {
    SettingsView(settings: SettingsManager())
}
