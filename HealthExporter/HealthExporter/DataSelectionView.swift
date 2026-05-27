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
        hasSelectedLabs
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

    private func updateExportEnabled() {
        exportEnabled = ExportLogic.isExportEnabled(
            exportWeight: settings.exportWeight,
            exportSteps: settings.exportSteps,
            exportGlucose: settings.exportGlucose,
            hasSelectedLabs: hasSelectedLabs,
            dateRangeOption: selectedDateRangeOption,
            startDate: startDate,
            endDate: endDate
        )
    }

    private func favoriteBinding(for loincCode: String) -> Binding<Bool> {
        Binding(
            get: { settings.favoriteLabCodes.contains(loincCode) },
            set: { newValue in
                if newValue {
                    settings.favoriteLabCodes.insert(loincCode)
                } else {
                    settings.favoriteLabCodes.remove(loincCode)
                }
            }
        )
    }

    private func panelBinding(for panel: LabPanel) -> Binding<Bool> {
        Binding(
            get: { settings.selectedLabPanels.contains(panel) },
            set: { newValue in
                if newValue {
                    settings.selectedLabPanels.insert(panel)
                } else {
                    settings.selectedLabPanels.remove(panel)
                }
            }
        )
    }

    private var panelsWithMetrics: [LabPanel] {
        LabPanel.allCases.filter { !LabMetricRegistry.metrics(in: $0).isEmpty }
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

    var body: some View {
        ZStack {
            VStack {
                Text("Select Data to Export")
                    .font(.largeTitle)
                    .padding()

                Toggle(isOn: $settings.exportWeight) {
                    Text("Weight")
                }
                .padding(.horizontal)
                .accessibilityIdentifier("weightToggle")

                Toggle(isOn: $settings.exportSteps) {
                    Text("Steps")
                }
                .padding(.horizontal)
                .accessibilityIdentifier("stepsToggle")

                Toggle(isOn: $settings.exportGlucose) {
                    Text("Blood Glucose (mg/dL)")
                }
                .padding(.horizontal)
                .accessibilityIdentifier("glucoseToggle")

                if !LabMetricRegistry.all.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lab Favorites")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ForEach(LabMetricRegistry.all) { metric in
                            HStack {
                                HStack(spacing: 4) {
                                    Text(metric.name)
                                    Image(systemName: "cross.case")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: favoriteBinding(for: metric.loincCode))
                                    .labelsHidden()
                                    .accessibilityIdentifier("favorite_\(metric.loincCode)")
                            }
                        }

                        if !panelsWithMetrics.isEmpty {
                            Text("Lab Panels")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)

                            ForEach(panelsWithMetrics, id: \.self) { panel in
                                Toggle(panel.displayName, isOn: panelBinding(for: panel))
                                    .accessibilityIdentifier("panel_\(panel.rawValue)")
                            }
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "cross.case")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("Requires access to Clinical Health Records")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                }

                Divider()
                    .padding()

                Text("Date Range")
                    .font(.headline)
                    .padding(.horizontal)

                Picker("Date Range", selection: $selectedDateRangeOption) {
                    ForEach(DateRangeOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .accessibilityIdentifier("dateRangePicker")

                // Last X Days Option
                if selectedDateRangeOption == .lastXDays {
                    VStack(spacing: 4) {
                        Text("Days:")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Picker("Days", selection: $settings.lastXDaysValue) {
                            ForEach(DataSelectionView.dayOptions, id: \.self) { days in
                                Text("\(days)").tag(days)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .accessibilityLabel("Number of days")

                        Text(DayRangeSummaryFormatter.summaryText(forDays: settings.lastXDaysValue, relativeTo: Date()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                }

                // Last X Records Option
                if selectedDateRangeOption == .lastXRecords {
                    VStack(spacing: 4) {
                        Text("Records:")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Picker("Records", selection: $settings.lastXRecordsValue) {
                            ForEach(DataSelectionView.recordOptions, id: \.self) { records in
                                Text("\(records)").tag(records)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                        .accessibilityLabel("Number of records")
                    }
                    .padding(.horizontal)
                }

                // Specific Date Range Option
                if selectedDateRangeOption == .specificDateRange {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Start Date")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        }

                        VStack(alignment: .leading) {
                            Text("End Date")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            DatePicker("", selection: $endDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        }
                    }
                    .padding()
                }

                Spacer()

                if !hasSelectedMetric {
                    Text("Please select at least one metric")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if selectedDateRangeOption == .specificDateRange && !isValidDateRange {
                    Text("End date must be on or after start date")
                        .font(.caption)
                        .foregroundColor(.red)
                }

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
                .padding()
                .accessibilityIdentifier("exportButton")
            }
            .padding()
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
        .onAppear { updateExportEnabled() }
        .onChange(of: settings.exportWeight) { updateExportEnabled() }
        .onChange(of: settings.exportSteps) { updateExportEnabled() }
        .onChange(of: settings.exportGlucose) { updateExportEnabled() }
        .onChange(of: settings.favoriteLabCodes) { updateExportEnabled() }
        .onChange(of: settings.selectedLabPanels) { updateExportEnabled() }
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
        healthManager.requestAuthorization(includeLabs: !metricsForFetch.isEmpty) { success, error in
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
            var weightFetchError: Error?
            var stepsFetchError: Error?
            var glucoseFetchError: Error?
            var labFetchError: Error?
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

            dispatchGroup.notify(queue: .main) {
                if let fetchError = ExportLogic.firstFetchError(
                    weightError: weightFetchError,
                    stepsError: stepsFetchError,
                    glucoseError: glucoseFetchError,
                    labError: labFetchError
                ) {
                    weightSamples = nil
                    stepsSamples = nil
                    glucoseSamples = nil
                    labResults = nil
                    isPreparingExport = false
                    errorMessage = fetchError.localizedDescription
                    showErrorAlert = true
                    return
                }

                let hasData = ExportLogic.hasAnyData(
                    weightSamples: weightSamples,
                    stepsSamples: stepsSamples,
                    glucoseSamples: glucoseSamples,
                    labResults: labResults
                )

                guard hasData else {
                    weightSamples = nil
                    stepsSamples = nil
                    glucoseSamples = nil
                    labResults = nil
                    isPreparingExport = false
                    errorMessage = ExportError.noDataFound.localizedDescription
                    showErrorAlert = true
                    return
                }

                let dateFormat = self.settings.dateFormat
                let weightUnit = self.settings.weightUnit
                let payload = PendingExportPayload(
                    weightSamples: weightSamples,
                    stepsSamples: stepsSamples,
                    glucoseSamples: glucoseSamples,
                    labResults: labResults
                )
                let estimate = CSVGenerator.makePreviewEstimate(
                    weightSamples: payload.weightSamples,
                    stepsSamples: payload.stepsSamples,
                    glucoseSamples: payload.glucoseSamples,
                    labResults: payload.labResults,
                    weightUnit: weightUnit,
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
