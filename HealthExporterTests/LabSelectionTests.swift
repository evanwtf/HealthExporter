@testable import HealthExporter
import Testing

struct LabSelectionTests {
    private let a1c = LOINCCode.hemoglobinA1C
    private var otherCodes: [String] {
        LabMetricRegistry.metrics(in: .other).map(\.loincCode)
    }

    private var lipidCodes: [String] {
        LabMetricRegistry.metrics(in: .lipid).map(\.loincCode)
    }

    private func selection(panels: Set<LabPanel> = [], favorites: Set<String> = []) -> LabSelection {
        LabSelection(panels: panels, favoriteCodes: favorites)
    }

    // MARK: - #115

    /// The user selects A1C on its own, turns the "Other" panel on, then off.
    @Test func panelOnThenOff_keepsALabSelectedOnItsOwn() {
        var labs = selection(favorites: [a1c])

        labs.setSelected(true, panel: .other)
        labs.setSelected(false, panel: .other)

        #expect(labs.isSelected(loincCode: a1c))
        #expect(labs.favoriteCodes == [a1c])
        #expect(labs.panels.isEmpty)
        #expect(!labs.isSelected(panel: .other))
        #expect(labs.selectedCount(in: .other) == 1)
    }

    @Test func panelOnThenOff_withNoSingleLabs_selectsNothing() {
        var labs = selection()

        labs.setSelected(true, panel: .lipid)
        labs.setSelected(false, panel: .lipid)

        #expect(labs == selection())
        #expect(ExportLogic.resolveLabMetrics(selectedPanels: labs.panels, favoriteCodes: labs.favoriteCodes).isEmpty)
    }

    @Test func panelOff_keepsSingleLabsInOtherPanels() {
        var labs = selection(panels: [.lipid], favorites: [a1c])

        labs.setSelected(false, panel: .lipid)

        #expect(labs.favoriteCodes == [a1c])
    }

    // MARK: - Panels

    @Test func panelOn_selectsEveryLabInIt() {
        var labs = selection()

        labs.setSelected(true, panel: .lipid)

        #expect(labs.isSelected(panel: .lipid))
        #expect(lipidCodes.allSatisfy { labs.isSelected(loincCode: $0) })
        #expect(labs.selectedCount(in: .lipid) == lipidCodes.count)
        #expect(!labs.isSelected(loincCode: a1c))
    }

    @Test func panelWithEveryLabSelectedOnItsOwn_showsAsOn() {
        let labs = selection(favorites: Set(lipidCodes))

        #expect(labs.isSelected(panel: .lipid))
    }

    /// A panel that is on only through single labs must turn off when tapped.
    @Test func panelOff_whenOnThroughSingleLabs_clearsThem() {
        var labs = selection(favorites: Set(lipidCodes).union([a1c]))

        labs.setSelected(false, panel: .lipid)

        #expect(!labs.isSelected(panel: .lipid))
        #expect(labs.selectedCount(in: .lipid) == 0)
        #expect(labs.favoriteCodes == [a1c])
    }

    // MARK: - Single labs

    @Test func singleLabOn_addsAFavorite() {
        var labs = selection()

        labs.setSelected(true, loincCode: a1c)

        #expect(labs.favoriteCodes == [a1c])
        #expect(labs.panels.isEmpty)
        #expect(!labs.isSelected(panel: .other))
        #expect(labs.selectedCount(in: .other) == 1)
    }

    @Test func singleLabOff_inASelectedPanel_keepsTheOtherLabsOn() throws {
        var labs = selection(panels: [.lipid])
        let first = try #require(lipidCodes.first)

        labs.setSelected(false, loincCode: first)

        #expect(!labs.isSelected(loincCode: first))
        #expect(labs.panels.isEmpty)
        #expect(labs.favoriteCodes == Set(lipidCodes.dropFirst()))
        #expect(labs.selectedCount(in: .lipid) == lipidCodes.count - 1)
    }

    @Test func singleLabOff_removesTheFavorite() {
        var labs = selection(favorites: [a1c])

        labs.setSelected(false, loincCode: a1c)

        #expect(labs == selection())
    }

    @Test func unknownCode_isNotSelectedThroughAPanel() {
        let labs = selection(panels: Set(LabPanel.allCases))

        #expect(!labs.isSelected(loincCode: "0000-0"))
    }

    @Test func otherPanelHasMoreThanOneLab() {
        // The #115 sequence needs A1C to share its panel with other labs.
        #expect(otherCodes.contains(a1c))
        #expect(otherCodes.count > 1)
    }
}
