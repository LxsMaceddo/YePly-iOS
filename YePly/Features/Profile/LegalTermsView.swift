import SwiftUI

struct LegalTermsView: View {
    @State private var searchText = ""

    private let document = LegalTermsDocument.load()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if document.containsContactPlaceholders {
                    contactPlaceholderWarning
                }

                if filteredSections.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 70)
                } else {
                    ForEach(filteredSections) { section in
                        termsBlock(section.markdown)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(YePlyTheme.background.ignoresSafeArea())
        .navigationTitle("Termos e direitos autorais")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Buscar nos termos"
        )
    }

    private var filteredSections: [LegalTermsSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return document.sections }

        return document.sections.filter {
            $0.markdown.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    private var contactPlaceholderWarning: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text("Contatos legais pendentes")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Substitua os três e-mails entre colchetes na seção 35 antes de publicar estes termos.")
                    .font(.caption)
                    .foregroundStyle(YePlyTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func termsBlock(_ markdown: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .font(.body)
                .foregroundStyle(.white.opacity(0.92))
                .tint(YePlyTheme.accent)
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(markdown)
                .font(.body)
                .foregroundStyle(.white.opacity(0.92))
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LegalTermsDocument {
    let rawText: String
    let sections: [LegalTermsSection]

    var containsContactPlaceholders: Bool {
        rawText.contains("[INSERT YEPLY SUPPORT EMAIL]")
            || rawText.contains("[INSERT COPYRIGHT EMAIL]")
            || rawText.contains("[INSERT PRIVACY EMAIL]")
    }

    static func load(bundle: Bundle = .main) -> LegalTermsDocument {
        let nestedURL = bundle.url(
            forResource: "TermsOfService",
            withExtension: "md",
            subdirectory: "Support"
        )
        let rootURL = bundle.url(forResource: "TermsOfService", withExtension: "md")
        let url = nestedURL ?? rootURL

        let text: String
        if let url, let bundledText = try? String(contentsOf: url, encoding: .utf8) {
            text = bundledText
        } else {
            text = "# Termos indisponíveis\n\nO documento TermsOfService.md não foi incluído no pacote do aplicativo."
        }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized
            .components(separatedBy: "\n---\n")
            .enumerated()
            .compactMap { index, block -> LegalTermsSection? in
                let clean = block.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return nil }
                return LegalTermsSection(id: index, markdown: clean)
            }

        return LegalTermsDocument(rawText: normalized, sections: blocks)
    }
}

private struct LegalTermsSection: Identifiable {
    let id: Int
    let markdown: String
}

#Preview {
    NavigationStack {
        LegalTermsView()
    }
    .preferredColorScheme(.dark)
}
