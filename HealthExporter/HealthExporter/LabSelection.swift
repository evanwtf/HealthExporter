import Foundation

/// The lab selection rules of the Choose Data screen.
///
/// A lab is selected when its panel is selected, or when the user selected it
/// on its own (a favorite). The two sets stay apart: turning a panel on or off
/// changes `panels`, not the labs the user selected on their own (#115).
nonisolated struct LabSelection: Equatable, Sendable {
    var panels: Set<LabPanel>
    var favoriteCodes: Set<String>

    func isSelected(loincCode: String) -> Bool {
        if favoriteCodes.contains(loincCode) {
            return true
        }
        guard let panel = LabMetricRegistry.metric(forLoincCode: loincCode)?.group else {
            return false
        }
        return panels.contains(panel)
    }

    /// A panel shows as on when it is selected, or when the user selected
    /// each of its labs on their own.
    func isSelected(panel: LabPanel) -> Bool {
        panels.contains(panel) || isEveryLabFavorite(in: panel)
    }

    func selectedCount(in panel: LabPanel) -> Int {
        LabMetricRegistry.metrics(in: panel).filter { isSelected(loincCode: $0.loincCode) }.count
    }

    mutating func setSelected(_ selected: Bool, loincCode: String) {
        if selected {
            favoriteCodes.insert(loincCode)
            return
        }
        // Turning one lab off in a selected panel keeps the panel's other labs on.
        if let panel = LabMetricRegistry.metric(forLoincCode: loincCode)?.group,
           panels.contains(panel)
        {
            let remainingCodes = LabMetricRegistry.metrics(in: panel)
                .map(\.loincCode)
                .filter { $0 != loincCode }
            panels.remove(panel)
            favoriteCodes.formUnion(remainingCodes)
        }
        favoriteCodes.remove(loincCode)
    }

    mutating func setSelected(_ selected: Bool, panel: LabPanel) {
        if selected {
            panels.insert(panel)
            return
        }
        panels.remove(panel)
        // The panel was on only because each of its labs was a favorite.
        // Turning it off must turn it off, so clear those labs.
        if isEveryLabFavorite(in: panel) {
            favoriteCodes.subtract(LabMetricRegistry.metrics(in: panel).map(\.loincCode))
        }
    }

    private func isEveryLabFavorite(in panel: LabPanel) -> Bool {
        let codes = LabMetricRegistry.metrics(in: panel).map(\.loincCode)
        return !codes.isEmpty && codes.allSatisfy { favoriteCodes.contains($0) }
    }
}
