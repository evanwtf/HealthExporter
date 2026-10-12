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
    var failureNotice: String?
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
    var healthStore: any HealthDataStore = HealthKitManager.shared

    @ScaledMetric(relativeTo: .body) private var dateRangeEditorMinHeight: CGFloat = 76
    @ScaledMetric(relativeTo: .title2) private var detailButtonSize: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tileColumnCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

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

    private func countLine(selected: Int, total: Int, noun: String) -> String {
        if selected == 0 || selected == total {
            return "\(total) \(noun)"
        }
        return "\(selected) of \(total) \(noun)"
    }

    private var weightDetail: String {
        settings.weightUnit == .kilograms ? "In kilograms" : "In pounds"
    }

    private func metricTile(
        _ category: HealthCategory,
        detail: String,
        isOn: Binding<Bool>,
        identifier: String
    ) -> some View {
        Toggle(category.name, isOn: isOn)
            .toggleStyle(CategoryTileToggleStyle(category: category, detail: detail))
            .accessibilityIdentifier(identifier)
    }

    private func tileWithDetails<Destination: View>(
        _ category: HealthCategory,
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        identifier: String,
        detailsIdentifier: String,
        detailsLabel: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Toggle(title, isOn: isOn)
                .toggleStyle(CategoryTileToggleStyle(
                    category: category,
                    detail: detail,
                    reservesTrailingAccessory: true
                ))
                .accessibilityIdentifier(identifier)

            NavigationLink(destination: destination()) {
                Image(systemName: "list.bullet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOn.wrappedValue ? Color.white : category.color)
                    .frame(width: detailButtonSize, height: detailButtonSize)
                    .background(
                        Circle().fill(isOn.wrappedValue ? Color.white.opacity(0.22) : category.color.opacity(0.14))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel(detailsLabel)
            .accessibilityIdentifier(detailsIdentifier)
        }
    }

    func labPanelDetail(_ panel: LabPanel) -> some View {
        SelectionDetailView(
            settings: settings,
            title: panel.displayName,
            category: .labs,
            rows: LabMetricRegistry.metrics(in: panel).map { metric in
                SelectionDetailRow(
                    id: metric.loincCode,
                    title: metric.name,
                    caption: "LOINC \(metric.loincCode)",
                    accessibilityIdentifier: "lab_\(metric.loincCode)",
                    isOn: labSelectionBinding(for: metric.loincCode)
                )
            }
        )
    }

    func vitalsDetail() -> some View {
        SelectionDetailView(
            settings: settings,
            title: "Vitals",
            category: .vitals,
            rows: VitalMetric.allCases.map { metric in
                SelectionDetailRow(
                    id: metric.rawValue,
                    title: metric.displayName,
                    caption: nil,
                    accessibilityIdentifier: "vital_\(metric.rawValue)",
                    isOn: vitalMetricBinding(for: metric)
                )
            }
        )
    }

    private func labPanelTile(_ panel: LabPanel) -> some View {
        let total = LabMetricRegistry.metrics(in: panel).count
        return tileWithDetails(
            .labs,
            title: panel.displayName,
            detail: countLine(selected: panelSelectedCount(panel), total: total, noun: total == 1 ? "lab" : "labs"),
            isOn: labPanelSelectionBinding(for: panel),
            identifier: "panel_\(panel.rawValue)",
            detailsIdentifier: "panelDetails_\(panel.rawValue)",
            detailsLabel: "Choose labs in \(panel.displayName)"
        ) {
            labPanelDetail(panel)
        }
    }

    private func vitalsTile() -> some View {
        tileWithDetails(
            .vitals,
            title: "Vitals",
            detail: countLine(
                selected: settings.selectedVitalMetrics.count,
                total: VitalMetric.allCases.count,
                noun: "vitals"
            ),
            isOn: vitalSectionBinding(),
            identifier: "vitalsSectionToggle",
            detailsIdentifier: "vitalsDetails",
            detailsLabel: "Choose vitals"
        ) {
            vitalsDetail()
        }
    }

    /// Lays tiles out in rows so each row takes the height of its tallest tile.
    private func tileGrid(_ tiles: [AnyView]) -> some View {
        let columns = tileColumnCount
        let rows = stride(from: 0, to: tiles.count, by: columns).map { start in
            Array(tiles[start..<min(start + columns, tiles.count)].enumerated())
        }
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                GridRow {
                    ForEach(rows[rowIndex], id: \.offset) { item in
                        item.element
                    }
                    if rows[rowIndex].count < columns {
                        Color.clear
                            .gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var measurementTiles: [AnyView] {
        [
            AnyView(metricTile(.weight, detail: weightDetail, isOn: $settings.exportWeight, identifier: "weightToggle")),
            AnyView(metricTile(.steps, detail: "Step count", isOn: $settings.exportSteps, identifier: "stepsToggle")),
            AnyView(metricTile(.glucose, detail: "Before/after meal tags", isOn: $settings.exportGlucose, identifier: "glucoseToggle")),
            AnyView(vitalsTile()),
        ]
    }

    private var labTiles: [AnyView] {
        LabPanel.allCases.map { AnyView(labPanelTile($0)) }
    }

    private func segmentLabel(for option: DateRangeOption) -> String {
        switch option {
        case .lastXDays:         return "Days"
        case .lastXRecords:      return "Records"
        case .specificDateRange: return "Range"
        case .allRecords:        return "All"
        }
    }

    private func dateRangeSegmentedPicker() -> some View {
        Picker("Date Range", selection: $selectedDateRangeOption) {
            ForEach(DateRangeOption.allCases, id: \.self) { option in
                Text(segmentLabel(for: option))
                    .accessibilityLabel(option.displayName)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
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
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dateRangeFooter() -> some View {
        VStack(spacing: 10) {
            dateRangeSegmentedPicker()

            dateRangeValueEditor()
                .frame(minHeight: dateRangeEditorMinHeight, alignment: .top)

            if !hasSelectedMetric {
                Text("Choose at least one type of data.")
                    .font(.caption)
                    .foregroundStyle(Color("ErrorText"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if selectedDateRangeOption == .specificDateRange && !isValidDateRange {
                Text("End date must be on or after start date")
                    .font(.caption)
                    .foregroundStyle(Color("ErrorText"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: {
                exportData()
            }) {
                Label("Export CSV", systemImage: "square.and.arrow.up")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Color("AccentColor"))
            .controlSize(.large)
            .disabled(!exportEnabled || isPreparingExport)
            .accessibilityIdentifier("exportButton")
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // A filled tile under the bare edge effect tints the controls; the
        // bar material keeps them legible and still hints at the tiles.
        .background(.bar)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tileGrid(measurementTiles)

                    sectionHeading("Lab results")
                        .padding(.top, 8)
                    tileGrid(labTiles)
                    Text("Lab sections require access to Clinical Health Records.")
                        .font(.footnote)
                        .foregroundStyle(Color("SecondaryText"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            // The footer is a bar, not a view below the grid, so tiles scroll
            // under it. A tile cut off by the footer shows that the grid continues.
            .scrollIndicatorsFlash(onAppear: true)
            .safeAreaBar(edge: .bottom) {
                dateRangeFooter()
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
        .fontDesign(.rounded)
        .tint(Color("AccentColor"))
        .navigationTitle("Choose Data")
        .navigationBarTitleDisplayMode(.large)
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
            contentTypes: [.commaSeparatedText],
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
        } onCancellation: {
            csvContent = ""
            isPreparingExport = false
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
        .alert(pendingExportPayload?.failureNotice == nil ? "Export Estimate" : "Some Data Could Not Be Read", isPresented: $showingEstimateConfirmation, presenting: pendingExportEstimate) { _ in
            Button("Cancel", role: .cancel) {
                clearPendingExport()
            }
            Button("Continue") {
                continuePendingExport()
            }
        } message: { estimate in
            Text([pendingExportPayload?.failureNotice, estimate.summaryText].compactMap { $0 }.joined(separator: "\n\n"))
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

        let request = ExportRequest(
            includeWeight: settings.exportWeight,
            includeSteps: settings.exportSteps,
            includeGlucose: settings.exportGlucose,
            labMetrics: labMetricsToFetch,
            vitalMetrics: settings.selectedVitalMetrics,
            dateRange: ExportLogic.dateRange(
                for: selectedDateRangeOption,
                lastXDays: settings.lastXDaysValue,
                specificStart: startDate,
                specificEnd: endDate
            ),
            recordLimit: ExportLogic.recordLimit(for: selectedDateRangeOption, lastXRecords: settings.lastXRecordsValue)
        )
        let loader = ExportDataLoader(store: healthStore)
        Task {
            do {
                try await loader.requestAuthorization(for: request)
            } catch {
                isPreparingExport = false
                logger.error("Authorization failed: \(error.localizedDescription)")
                errorMessage = ExportError.healthKitAuthorizationFailed(underlying: error).localizedDescription
                showErrorAlert = true
                return
            }

            let result = await loader.load(request)
            if let message = result.blockingErrorMessage {
                isPreparingExport = false
                errorMessage = message
                showErrorAlert = true
                return
            }

            let payload = PendingExportPayload(
                weightSamples: result.weightSamples,
                stepsSamples: result.stepsSamples,
                glucoseSamples: result.glucoseSamples,
                labResults: result.labResults,
                vitalSamples: result.vitalSamples,
                failureNotice: result.partialFailureNotice
            )
            let estimate = CSVGenerator.makePreviewEstimate(
                weightSamples: payload.weightSamples,
                stepsSamples: payload.stepsSamples,
                glucoseSamples: payload.glucoseSamples,
                labResults: payload.labResults,
                vitalSamples: payload.vitalSamples,
                weightUnit: settings.weightUnit,
                temperatureUnit: settings.temperatureUnit,
                dateFormat: settings.dateFormat
            )

            clearPendingExport()
            pendingExportPayload = payload
            pendingExportEstimate = estimate

            if estimate.shouldShowConfirmation || payload.failureNotice != nil {
                isPreparingExport = false
                showingEstimateConfirmation = true
            } else {
                continuePendingExport()
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
        csvContent = CSVGenerator.generateCombinedCSV(
            weightSamples: &payload.weightSamples,
            stepsSamples: &payload.stepsSamples,
            glucoseSamples: &payload.glucoseSamples,
            labResults: &payload.labResults,
            vitalSamples: &payload.vitalSamples,
            weightUnit: weightUnit,
            temperatureUnit: temperatureUnit,
            dateFormat: dateFormat,
            sortOrder: sortOrder
        )

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
