import FeedingCore
import SwiftUI

/// The household's own short list of medicines and vitamins (`06-more-than-feeds.md`): it starts
/// with Vitamin D. Both phones share it. Opened from Settings and from the Medicine tile's "+".
struct MedicineListEditor: View {
    private let model = AppModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @FocusState private var adding: Bool

    /// A form: a night return leaves it in front (eng2 D3), wherever it was opened from.
    var body: some View {
        form.modifier(FormOnScreen())
    }

    @ViewBuilder
    private var form: some View {
        let medicines = model.store.data.medicines
        Form {
            Section {
                ForEach(medicines, id: \.self) { name in
                    HStack(spacing: 10) {
                        FeedMarkView(.medicine, size: 18, relativeTo: .body)
                        Text(name)
                    }
                }
                .onDelete { offsets in
                    var list = medicines
                    list.remove(atOffsets: offsets)
                    save(list)
                }
                .onMove { from, to in
                    var list = medicines
                    list.move(fromOffsets: from, toOffset: to)
                    save(list)
                }
                HStack(spacing: 8) {
                    TextField("Add a medicine or vitamin", text: $newName)
                        .focused($adding)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .feedText(.smallButton)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .tint(Theme.text)
                }
            } header: {
                Text("On Home").feedText(.label).foregroundStyle(Theme.textMuted)
            } footer: {
                Text("Each one gets a Given button on Home, and shows when it was last given. Both phones share this list.")
                    .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(Theme.text)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Medicines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Medicines").feedText(.dayHeading).accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.tint(Theme.text)
            }
            ToolbarItem(placement: .topBarLeading) {
                EditButton().tint(Theme.text)
            }
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        save(model.store.data.medicines + [name])
        newName = ""
    }

    private func save(_ list: [String]) {
        model.store.change { $0.setMedicines(list, now: Date()) }
    }
}
