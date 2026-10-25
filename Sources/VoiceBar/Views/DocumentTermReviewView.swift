import SwiftUI
import VoiceBarCore

struct DocumentTermReviewView: View {
    private struct EditableCandidate: Identifiable {
        let id: String
        var spelling: String
        var selected: Bool
        let occurrenceCount: Int
        let evidence: [DocumentTermEvidence]
    }

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [EditableCandidate]
    private let importSummary: String
    private let onAdd: ([String]) -> Void

    init(candidates: [DocumentTermCandidate], importSummary: String, onAdd: @escaping ([String]) -> Void) {
        _candidates = State(initialValue: candidates.map {
            EditableCandidate(
                id: $0.id,
                spelling: $0.term,
                selected: false,
                occurrenceCount: $0.occurrenceCount,
                evidence: $0.evidence
            )
        })
        self.importSummary = importSummary
        self.onAdd = onAdd
    }

    private var selectedCount: Int { candidates.filter(\.selected).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Проверьте найденные термины")
                .font(.title2.weight(.semibold))
            Text("Ничего не добавится, пока вы не выберете и не подтвердите термины. При необходимости исправьте написание.")
                .foregroundStyle(.secondary)
            Text(importSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Предложения: \(candidates.count)")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Выбрать все") { candidates.indices.forEach { candidates[$0].selected = true } }
                Button("Снять выбор") { candidates.indices.forEach { candidates[$0].selected = false } }
            }

            List {
                ForEach($candidates) { $candidate in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("", isOn: $candidate.selected)
                            .labelsHidden()
                            .accessibilityLabel("Добавить термин \(candidate.spelling)")
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                TextField("Термин", text: $candidate.spelling)
                                    .textFieldStyle(.roundedBorder)
                                Text("×\(candidate.occurrenceCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 34, alignment: .trailing)
                            }
                            ForEach(candidate.evidence.prefix(2)) { evidence in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(evidence.sourceName + (evidence.pageNumber.map { " · стр. \($0)" } ?? ""))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text(evidence.excerpt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                Spacer()
                Button("Отмена", role: .cancel) { dismiss() }
                Button("Добавить выбранные (\(selectedCount))") {
                    let terms = candidates
                        .filter(\.selected)
                        .map { $0.spelling.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    onAdd(terms)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCount == 0)
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 520)
    }
}
