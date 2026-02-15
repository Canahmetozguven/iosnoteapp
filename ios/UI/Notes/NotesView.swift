import SwiftUI
import SwiftData

struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                ForEach(notes) { note in
                    NavigationLink(value: note) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title.isEmpty ? "Untitled Note" : note.title)
                                .font(.headline)
                                .foregroundStyle(note.title.isEmpty ? .secondary : .primary)
                            
                            if !note.content.isEmpty {
                                Text(note.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            
                            Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteNotes)
            }
            .navigationTitle("Notes")
            .navigationDestination(for: Note.self) { note in
                NoteEditorView(note: note)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addNote) {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .overlay {
                if notes.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "note.text",
                        description: Text("Tap the compose button to create your first note.")
                    )
                }
            }
        }
    }
    
    private func addNote() {
        let newNote = Note(title: "", content: "")
        modelContext.insert(newNote)
        // Navigate to the new note
        navigationPath.append(newNote)
    }
    
    private func deleteNotes(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(notes[index])
            }
        }
    }
}
