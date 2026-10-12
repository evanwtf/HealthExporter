import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @Environment(\.dismiss) var dismiss
    @State private var testDataMessage = ""
    @State private var showTestDataFailureAlert = false

    let healthManager = HealthKitManager()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto-dismiss save confirmation", isOn: $settings.autoDismissSaveConfirmation)
                        .accessibilityIdentifier("autoDismissSaveConfirmationToggle")
                } header: {
                    sectionHeader("Export Behavior")
                } footer: {
                    Text("Closes the save confirmation after 5 seconds.")
                }

                Section(header: sectionHeader("Export Format")) {
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
                }

                Section(header: sectionHeader("Units")) {
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
                }

                #if targetEnvironment(simulator)
                Section(header: sectionHeader("Testing")) {
                    Button("Generate Weight Data", action: generateTestData)

                    if !testDataMessage.isEmpty {
                        Text(testDataMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif

                Section(header: sectionHeader("About")) {
                    NavigationLink(destination: PrivacyPolicyView()) {
                        Text("Privacy Policy & Disclaimer")
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                            .monospacedDigit()
                            .foregroundStyle(Color("InkSecondary"))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("Paper"))
            .tint(.accentColor)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.headline)
                        .fontDesign(.serif)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3)
            .fontWeight(.semibold)
            .fontDesign(.serif)
            .foregroundStyle(Color("Ink"))
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    #if targetEnvironment(simulator)
    private func generateTestData() {
        healthManager.generateTestData { success, error in
            if success {
                testDataMessage = "✓ Weight data generated (60 days)"
            } else {
                testDataMessage = "✗ \(HealthKitQueryHelpers.simulatorTestDataFailureMessage(error))"
                showTestDataFailureAlert = true
            }
        }
    }
    #endif
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: SettingsManager())
    }
}
