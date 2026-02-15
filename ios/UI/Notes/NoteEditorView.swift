import SwiftUI
import SwiftData

struct NoteEditorView: View {
    @Bindable var note: Note
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Title", text: $note.title, axis: .vertical)
                .font(.system(size: 28, weight: .bold))
                .padding(.horizontal)
                .padding(.top)
            
            TextEditor(text: $note.content)
                .font(.body)
                .padding(.horizontal)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .onChange(of: note.title) { _ in
            note.updatedAt = Date()
        }
        .onChange(of: note.content) { _ in
            note.updatedAt = Date()
        }
    }
}
