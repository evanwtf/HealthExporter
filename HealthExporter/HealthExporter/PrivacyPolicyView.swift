import SwiftUI

/// Shows `PrivacyPolicy`. The text lives there, so the web copy can be
/// checked against it.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Last updated: \(PrivacyPolicy.lastUpdated)")
                    .font(.caption)
                    .foregroundStyle(Color("SecondaryText"))

                ForEach(PrivacyPolicy.policy, id: \.title) { section in
                    sectionView(section)
                }

                Divider()
                    .padding(.vertical, 8)

                Text("Disclaimer")
                    .font(.title)
                    .fontWeight(.bold)

                ForEach(PrivacyPolicy.disclaimer, id: \.title) { section in
                    sectionView(section)
                }

                Divider()
                    .padding(.vertical, 8)

                sectionView(PrivacyPolicy.contact)
            }
            .padding()
        }
        .fontDesign(.rounded)
        .tint(Color("AccentColor"))
        .navigationTitle("Privacy & Disclaimer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionView(_ section: PolicySection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.headline)
            Text(Self.markdown(section.body))
                .font(.body)
            if !section.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(section.bullets, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\u{2022}")
                                .fontWeight(.heavy)
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                            Text(Self.markdown(item))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.body)
                .padding(.leading, 4)
                .padding(.top, 4)
            }
            if let closing = section.closing {
                Text(Self.markdown(closing))
                    .font(.body)
                    .padding(.top, 4)
            }
        }
    }

    /// Renders inline Markdown, so a link in the policy text can be tapped.
    nonisolated static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
