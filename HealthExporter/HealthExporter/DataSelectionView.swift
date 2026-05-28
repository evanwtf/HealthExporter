import SwiftUI
import UniformTypeIdentifiers
import HealthKit
import os

private let logger = Logger(subsystem: "com.HealthExporter", category: "DataSelection")

private struct PendingExportPayload {
    var weightSamples: [HKQuantitySample]?
    var stepsSamples: [HKQuantitySample]?
    var glucoseSamples: [GlucoseSampleMgDl]?
    var labResults: [LabResultSample]?
    var vitalSamples: [VitalMetricComponent: [HKQuantitySample]]
}

struct DataSelectionView: View {
    @State private var showingExporter = false
    @State private var csvContent = ""
    @State private var fileName = ""
    @State private var selectedDateRangeOption: DateRangeOption = .lastXDays
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var showingSaveSuccess = false
    @State private var saveSuccessDismissTask: Task<Void, Never>?
    @State private var showingEstimateConfirmation = false
    @State private var isPreparingExport = false
    @State private var exportEnabled = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var pendingExportPayload: PendingExportPayload?
    @State private var pendingExportEstimate: ExportPreviewEstimate?

    @ObservedObject var settings: SettingsManager
    let healthManager = HealthKitManager()

    private static let dayOptions = Array(1...30) + [60, 90, 180, 365, 730]
    private static let recordOptions = Array(stride(from: 100, through: 1_000, by: 100)) + Array(stride(from: 2_000, through: 10_000, by: 1_000))
    private static let saveSuccessAutoDismissSeconds = 5

    private var isValidDateRange: Bool {
        startDate <= endDate
    }

    private var hasSelectedMetric: Bool {
        settings.exportWeight ||
        settings.exportSteps ||
        settings.exportGlucose ||
        hasSelectedLabs ||
        hasSelectedVitals
    }

    private var hasSelectedLabs: Bool {
        !labMetricsToFetch.isEmpty
    }

    private var labMetricsToFetch: [LabMetric] {
        ExportLogic.resolveLabMetrics(
            selectedPanels: settings.selectedLabPanels,
            favoriteCodes: settings.favoriteLabCodes
        )
    }

    private var hasSelectedVitals: Bool {
        !settings.selectedVitalMetrics.isEmpty
    }

    private var vitalComponentsToFetch: [VitalMetricComponent] {
        let components = Set(settings.selectedVitalMetrics.flatMap(\.components))
        return VitalMetricComponent.allCases.filter { components.contains($0) }
    }

    private func updateExportEnabled() {
        exportEnabled = ExportLogic.isExportEnabled(
            exportWeight: settings.exportWeight,
            exportSteps: settings.exportSteps,
            exportGlucose: settings.exportGlucose,
            hasSelectedLabs: hasSelectedLabs,
            hasSelectedVitals: hasSelectedVitals,
            dateRangeOption: selectedDateRangeOption,
            startDate: startDate,
            endDate: endDate
        )
    }

    private func labSelectionBinding(for loincCode: String) -> Binding<Bool> {
        Binding(
            get: {
                if settings.favoriteLabCodes.contains(loincCode) {
                    return true
                }
                guard let panel = LabMetricRegistry.metric(forLoincCode: loincCode)?.group else {
                    return false
                }
                return settings.selectedLabPanels.contains(panel)
            },
            set: { newValue in
                if newValue {
                    settings.favoriteLabCodes.insert(loincCode)
                } else {
                    if let panel = LabMetricRegistry.metric(forLoincCode: loincCode)?.group,
                       settings.selectedLabPanels.contains(panel) {
                        let remainingCodes = LabMetricRegistry.metrics(in: panel)
                            .map(\.loincCode)
                            .filter { $0 != loincCode }
                        settings.selectedLabPanels.remove(panel)
                        settings.favoriteLabCodes.formUnion(remainingCodes)
                    }
                    settings.favoriteLabCodes.remove(loincCode)
                }
            }
        )
    }

    private func labPanelSelectionBinding(for panel: LabPanel) -> Binding<Bool> {
        Binding(
            get: {
                let codes = LabMetricRegistry.metrics(in: panel).map(\.loincCode)
                return settings.selectedLabPanels.contains(panel) || (!codes.isEmpty && codes.allSatisfy { settings.favoriteLabCodes.contains($0) })
            },
            set: { newValue in
                let codes = LabMetricRegistry.metrics(in: panel).map(\.loincCode)
                if newValue {
                    settings.favoriteLabCodes.formUnion(codes)
                    settings.selectedLabPanels.insert(panel)
                } else {
                    settings.favoriteLabCodes.subtract(codes)
                    settings.selectedLabPanels.remove(panel)
                }
            }
        )
    }

    private func panelExpansionBinding(for panel: LabPanel) -> Binding<Bool> {
        Binding(
            get: { settings.expandedLabPanels.contains(panel) },
            set: { newValue in
                if newValue {
                    settings.expandedLabPanels.insert(panel)
                } else {
                    settings.expandedLabPanels.remove(panel)
                }
            }
        )
    }

    private func vitalMetricBinding(for metric: VitalMetric) -> Binding<Bool> {
        Binding(
            get: { settings.selectedVitalMetrics.contains(metric) },
            set: { newValue in
                if newValue {
                    settings.selectedVitalMetrics.insert(metric)
                } else {
                    settings.selectedVitalMetrics.remove(metric)
                }
            }
        )
    }

    private func vitalSectionBinding() -> Binding<Bool> {
        Binding(
            get: {
                VitalMetric.allCasesSet.isSubset(of: settings.selectedVitalMetrics)
            },
            set: { newValue in
                if newValue {
                    settings.selectedVitalMetrics.formUnion(VitalMetric.allCasesSet)
                } else {
                    settings.selectedVitalMetrics.removeAll()
                }
            }
        )
    }

    private func panelSelectedCount(_ panel: LabPanel) -> Int {
        LabMetricRegistry.metrics(in: panel).reduce(0) { count, metric in
            let isSelected = settings.favoriteLabCodes.contains(metric.loincCode) ||
                settings.selectedLabPanels.contains(panel)
            return count + (isSelected ? 1 : 0)
        }
    }

    private func presentSaveSuccessConfirmation() {
        showingSaveSuccess = true

        guard settings.autoDismissSaveConfirmation else {
            cancelSaveSuccessDismissTask()
            return
        }

        cancelSaveSuccessDismissTask()
        saveSuccessDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.saveSuccessAutoDismissSeconds) * 1_000_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled, showingSaveSuccess else { return }
            showingSaveSuccess = false
        }
    }

    private func dismissSaveSuccessConfirmation() {
        cancelSaveSuccessDismissTask()
        showingSaveSuccess = false
    }

    private func cancelSaveSuccessDismissTask() {
        saveSuccessDismissTask?.cancel()
        saveSuccessDismissTask = nil
    }

    private func labPanelDisclosure(_ panel: LabPanel) -> some View {
        let metrics = LabMetricRegistry.metrics(in: panel)
        let selectedCount = panelSelectedCount(panel)
        return DisclosureGroup(isExpanded: panelExpansionBinding(for: panel)) {
            ForEach(metrics) { metric in
                Toggle(metric.name, isOn: labSelectionBinding(for: metric.loincCode))
                    .accessibilityIdentifier("lab_\(metric.loincCode)")
            }
        } label: {
            Toggle(isOn: labPanelSelectionBinding(for: panel)) {
                HStack(spacing: 6) {
                    Text(panel.displayName)
                    if !metrics.isEmpty {
                        Text("\(selectedCount)/\(metrics.count)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityIdentifier("panel_\(panel.rawValue)")
        }
    }

    private func vitalsDisclosure() -> some View {
        let allVitals = VitalMetric.allCases
        let selectedCount = settings.selectedVitalMetrics.count
        return DisclosureGroup(isExpanded: $settings.expandedVitalsSection) {
            ForEach(allVitals) { metric in
                Toggle(metric.displayName, isOn: vitalMetricBinding(for: metric))
                    .accessibilityIdentifier("vital_\(metric.rawValue)")
            }
        } label: {
            Toggle(isOn: vitalSectionBinding()) {
                HStack(spacing: 6) {
                    Text("Vitals")
                    if !allVitals.isEmpty {
                        Text("\(selectedCount)/\(allVitals.count)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityIdentifier("vitalsSectionToggle")
        }
    }

    private static let dateRangeEditorHeight: CGFloat = 90

    private func segmentLabel(for option: DateRangeOption) -> String {
        switch option {
        case .lastXDays:         return "Last X\nDays"
        case .lastXRecords:      return "Last X\nRecords"
        case .specificDateRange: return "Specific\nDates"
        case .allRecords:        return "All\nRecords"
        }
    }

    private func dateRangeSegmentedPicker() -> some View {
        HStack(spacing: 2) {
            ForEach(DateRangeOption.allCases, id: \.self) { option in
                let isSelected = selectedDateRangeOption == option
                Button {
                    selectedDateRangeOption = option
                } label: {
                    Text(segmentLabel(for: option))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isSelected ? Color(uiColor: .systemBackground) : Color.clear)
                                .shadow(color: isSelected ? Color.black.opacity(0.12) : .clear, radius: 1, y: 1)
                        )
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayName)
            }
        }
        .padding(2)
        .background(Color(uiColor: .tertiarySystemFill))
        .cornerRadius(9)
        .accessibilityIdentifier("dateRangePicker")
    }

    @ViewBuilder
    private func dateRangeValueEditor() -> some View {
        switch selectedDateRangeOption {
        case .lastXDays:
            VStack(spacing: 6) {
                HStack {
                    Text("Days:")
                        .font(.subheadline)
                    Spacer()
                    Picker("Days", selection: $settings.lastXDaysValue) {
                        ForEach(DataSelectionView.dayOptions, id: \.self) { days in
                            Text("\(days)").tag(days)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Number of days")
                }
                Text(DayRangeSummaryFormatter.summaryText(forDays: settings.lastXDaysValue, relativeTo: Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .lastXRecords:
            HStack {
                Text("Records:")
                    .font(.subheadline)
                Spacer()
                Picker("Records", selection: $settings.lastXRecordsValue) {
                    ForEach(DataSelectionView.recordOptions, id: \.self) { records in
                        Text("\(records)").tag(records)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Number of records")
            }

        case .specificDateRange:
            VStack(spacing: 6) {
                HStack {
                    Text("Start:")
                        .font(.subheadline)
                    Spacer()
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden()
                }
                HStack {
                    Text("End:")
                        .font(.subheadline)
                    Spacer()
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }

        case .allRecords:
            Text("Exports every available record in the selected metrics.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dateRangeFooter() -> some View {
        VStack(spacing: 10) {
            dateRangeSegmentedPicker()

            dateRangeValueEditor()
                .frame(height: Self.dateRangeEditorHeight, alignment: .top)

            if !hasSelectedMetric {
                Text("Please select at least one metric")
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if selectedDateRangeOption == .specificDateRange && !isValidDateRange {
                Text("End date must be on or after start date")
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        Toggle("Weight", isOn: $settings.exportWeight)
                            .accessibilityIdentifier("weightToggle")
                        Toggle("Steps", isOn: $settings.exportSteps)
                            .accessibilityIdentifier("stepsToggle")
                        Toggle("Blood Glucose (mg/dL)", isOn: $settings.exportGlucose)
                            .accessibilityIdentifier("glucoseToggle")
                    } header: {
                        Label("Activity & Glucose", systemImage: "figure.walk")
                    }

                    Section {
                        ForEach(LabPanel.allCases, id: \.self) { panel in
                            labPanelDisclosure(panel)
                        }
                    } header: {
                        Label("Labs", systemImage: "cross.case")
                    } footer: {
                        Text("Lab sections require access to Clinical Health Records.")
                    }

                    Section {
                        vitalsDisclosure()
                    } header: {
                        Label("Vitals", systemImage: "heart.text.square")
                    }
                }

                dateRangeFooter()

                Button(action: {
                    exportData()
                }) {
                    Text("Save...")
                        .font(.title3)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(exportEnabled ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(!exportEnabled || isPreparingExport)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .accessibilityIdentifier("exportButton")
            }
            .disabled(isPreparingExport)

            if isPreparingExport {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()

                ProgressView("Preparing export...")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .navigationTitle("Select Data to Export")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { updateExportEnabled() }
        .onChange(of: settings.exportWeight) { updateExportEnabled() }
        .onChange(of: settings.exportSteps) { updateExportEnabled() }
        .onChange(of: settings.exportGlucose) { updateExportEnabled() }
        .onChange(of: settings.favoriteLabCodes) { updateExportEnabled() }
        .onChange(of: settings.selectedLabPanels) { updateExportEnabled() }
        .onChange(of: settings.selectedVitalMetrics) { updateExportEnabled() }
        .onChange(of: selectedDateRangeOption) { updateExportEnabled() }
        .onChange(of: startDate) { updateExportEnabled() }
        .onChange(of: endDate) { updateExportEnabled() }
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(content: csvContent),
            contentType: .commaSeparatedText,
            defaultFilename: fileName
        ) { result in
            switch result {
            case .success(let url):
                logger.info("File saved to: \(url.path)")
                presentSaveSuccessConfirmation()
                csvContent = ""
                isPreparingExport = false
            case .failure(let error):
                logger.error("Error saving file: \(error.localizedDescription)")
                csvContent = ""
                isPreparingExport = false
                errorMessage = ExportError.fileWriteFailed(underlying: error).localizedDescription
                showErrorAlert = true
            }
        }
        .onDisappear {
            csvContent = ""
            isPreparingExport = false
            cancelSaveSuccessDismissTask()
            clearPendingExport()
        }
        .alert("File saved!", isPresented: $showingSaveSuccess) {
            Button("Close") {
                dismissSaveSuccessConfirmation()
            }
        } message: {
            Text("File \(fileName) has been saved!")
        }
        .alert("Export Estimate", isPresented: $showingEstimateConfirmation, presenting: pendingExportEstimate) { _ in
            Button("Cancel", role: .cancel) {
                clearPendingExport()
            }
            Button("Continue") {
                continuePendingExport()
            }
        } message: { estimate in
            Text(estimate.summaryText)
        }
        .alert("Export Error", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private func exportData() {
        dismissSaveSuccessConfirmation()
        isPreparingExport = true

        let metricsForFetch = labMetricsToFetch
        let vitalMetricsForFetch = settings.selectedVitalMetrics
        let vitalComponentsForFetch = vitalComponentsToFetch
        healthManager.requestAuthorization(includeLabs: !metricsForFetch.isEmpty, vitalMetrics: vitalMetricsForFetch) { success, error in
            guard success else {
                DispatchQueue.main.async {
                    isPreparingExport = false
                    logger.error("Authorization failed: \(error?.localizedDescription ?? "Unknown error")")
                    errorMessage = ExportError.healthKitAuthorizationFailed(underlying: error).localizedDescription
                    showErrorAlert = true
                }
                return
            }

            var weightSamples: [HKQuantitySample]? = nil
            var stepsSamples: [HKQuantitySample]? = nil
            var glucoseSamples: [GlucoseSampleMgDl]? = nil
            var labResults: [LabResultSample]? = nil
            var vitalSamples: [VitalMetricComponent: [HKQuantitySample]] = [:]
            var weightFetchError: Error?
            var stepsFetchError: Error?
            var glucoseFetchError: Error?
            var labFetchError: Error?
            var vitalFetchError: Error?
            let dispatchGroup = DispatchGroup()

            let dateRange = ExportLogic.dateRange(
                for: self.selectedDateRangeOption,
                lastXDays: self.settings.lastXDaysValue,
                specificStart: self.startDate,
                specificEnd: self.endDate
            )
            let recordLimit = ExportLogic.recordLimit(
                for: self.selectedDateRangeOption,
                lastXRecords: self.settings.lastXRecordsValue
            )

            if settings.exportWeight {
                dispatchGroup.enter()
                healthManager.fetchWeightData(dateRange: dateRange, limit: recordLimit) { samples, error in
                    DispatchQueue.main.async {
                        weightSamples = samples
                        weightFetchError = error
                        dispatchGroup.leave()
                    }
                }
            }

            if settings.exportSteps {
                dispatchGroup.enter()
                healthManager.fetchStepsData(dateRange: dateRange, limit: recordLimit) { samples, error in
                    DispatchQueue.main.async {
                        stepsSamples = samples
                        stepsFetchError = error
                        dispatchGroup.leave()
                    }
                }
            }

            if settings.exportGlucose {
                dispatchGroup.enter()
                healthManager.fetchBloodGlucoseDataTyped(dateRange: dateRange, limit: recordLimit) { samples, error in
                    DispatchQueue.main.async {
                        glucoseSamples = samples
                        glucoseFetchError = error
                        dispatchGroup.leave()
                    }
                }
            }

            if !metricsForFetch.isEmpty {
                dispatchGroup.enter()
                healthManager.fetchLabResults(metrics: metricsForFetch, dateRange: dateRange, limit: recordLimit) { samples, error in
                    DispatchQueue.main.async {
                        labResults = samples
                        labFetchError = error
                        dispatchGroup.leave()
                    }
                }
            }

            for component in vitalComponentsForFetch {
                dispatchGroup.enter()
                healthManager.fetchVitalData(component: component, dateRange: dateRange, limit: recordLimit) { samples, error in
                    DispatchQueue.main.async {
                        vitalSamples[component] = samples ?? []
                        // Surface the first vital component error; downstream code reports a single error
                        // for the whole vitals group rather than overwhelming the user with per-component failures.
                        if vitalFetchError == nil {
                            vitalFetchError = error
                        }
                        dispatchGroup.leave()
                    }
                }
            }

            dispatchGroup.notify(queue: .main) {
                if let fetchError = ExportLogic.firstFetchError(
                    weightError: weightFetchError,
                    stepsError: stepsFetchError,
                    glucoseError: glucoseFetchError,
                    labError: labFetchError,
                    vitalError: vitalFetchError
                ) {
                    weightSamples = nil
                    stepsSamples = nil
                    glucoseSamples = nil
                    labResults = nil
                    vitalSamples.removeAll()
                    isPreparingExport = false
                    errorMessage = fetchError.localizedDescription
                    showErrorAlert = true
                    return
                }

                let hasData = ExportLogic.hasAnyData(
                    weightSamples: weightSamples,
                    stepsSamples: stepsSamples,
                    glucoseSamples: glucoseSamples,
                    labResults: labResults,
                    vitalSamples: vitalSamples
                )

                guard hasData else {
                    weightSamples = nil
                    stepsSamples = nil
                    glucoseSamples = nil
                    labResults = nil
                    vitalSamples.removeAll()
                    isPreparingExport = false
                    errorMessage = ExportError.noDataFound.localizedDescription
                    showErrorAlert = true
                    return
                }

                let dateFormat = self.settings.dateFormat
                let weightUnit = self.settings.weightUnit
                let temperatureUnit = self.settings.temperatureUnit
                let payload = PendingExportPayload(
                    weightSamples: weightSamples,
                    stepsSamples: stepsSamples,
                    glucoseSamples: glucoseSamples,
                    labResults: labResults,
                    vitalSamples: vitalSamples
                )
                let estimate = CSVGenerator.makePreviewEstimate(
                    weightSamples: payload.weightSamples,
                    stepsSamples: payload.stepsSamples,
                    glucoseSamples: payload.glucoseSamples,
                    labResults: payload.labResults,
                    vitalSamples: payload.vitalSamples,
                    weightUnit: weightUnit,
                    temperatureUnit: temperatureUnit,
                    dateFormat: dateFormat
                )

                clearPendingExport()
                pendingExportPayload = payload
                pendingExportEstimate = estimate

                if estimate.shouldShowConfirmation {
                    isPreparingExport = false
                    showingEstimateConfirmation = true
                } else {
                    continuePendingExport()
                }
            }
        }
    }

    private func continuePendingExport() {
        guard var payload = pendingExportPayload else { return }

        isPreparingExport = true
        clearPendingExport()

        let dateFormat = settings.dateFormat
        let sortOrder = settings.sortOrder
        let weightUnit = settings.weightUnit
        let temperatureUnit = settings.temperatureUnit
        var csv = CSVGenerator.csvHeader + "\n"

        if var samples = payload.weightSamples {
            payload.weightSamples = nil
            CSVGenerator.appendWeightRows(to: &csv, samples: &samples, unit: weightUnit, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        if var samples = payload.stepsSamples {
            payload.stepsSamples = nil
            CSVGenerator.appendStepsRows(to: &csv, samples: &samples, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        if var samples = payload.glucoseSamples {
            payload.glucoseSamples = nil
            CSVGenerator.appendGlucoseRows(to: &csv, samples: &samples, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        if var samples = payload.labResults {
            payload.labResults = nil
            CSVGenerator.appendLabResultRows(to: &csv, samples: &samples, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        if !payload.vitalSamples.isEmpty {
            CSVGenerator.appendVitalRows(to: &csv, samplesByComponent: &payload.vitalSamples, temperatureUnit: temperatureUnit, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        csvContent = csv

        fileName = ExportLogic.exportFilename()

        isPreparingExport = false
        showingExporter = true
    }

    private func clearPendingExport() {
        pendingExportPayload = nil
        pendingExportEstimate = nil
    }
}

struct DataSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        DataSelectionView(settings: SettingsManager())
    }
}
