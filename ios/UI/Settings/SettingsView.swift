import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(GlobalViewModel.self) var vm
    @Query private var notes: [Note]
    
    var body: some View {
        NavigationStack {
            List {
                Section("Model Management") {
                    if vm.modelManager.models.isEmpty {
                        Text("No models found in Documents.")
                            .foregroundStyle(.secondary)
                        Text("Drag & Drop .gguf files via Finder/iTunes")
                            .font(.caption)
                    } else {
                        ForEach(vm.modelManager.models, id: \.self) { model in
                            HStack {
                                Text(model)
                                Spacer()
                                if vm.currentModelName == model {
                                    if vm.isBusy {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.greenSuccess)
                                    }
                                } else {
                                    Button("Load") {
                                        vm.loadModel(filename: model)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(vm.isBusy)
                                }
                            }
                        }
                    }
                }
                
                Section("Status") {
                    HStack {
                        Text("Loaded Model")
                        Spacer()
                        Text(vm.currentModelName ?? "None")
                            .foregroundStyle(.secondary)
                    }
                    if let error = vm.loadingError {
                        Text("Error: \(error)")
                            .foregroundStyle(AppTheme.redError)
                            .font(.caption)
                    }
                }
                
                Section("Performance") {
                    Toggle("Low Power Mode", isOn: Bindable(vm).isLowPowerMode)
                    Text("Forces CPU usage and reduces context size (2048). Recommended for resource-constrained environments.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("RAG Indexing") {
                    let indexedCount = notes.filter { $0.embedding != nil }.count
                    
                    HStack {
                        Text("Notes")
                        Spacer()
                        Text("\(indexedCount)/\(notes.count) indexed")
                            .foregroundStyle(.secondary)
                    }
                    
                    if vm.indexingProgress > 0 && vm.indexingProgress < 1.0 {
                        ProgressView(value: vm.indexingProgress)
                    }
                    
                    if let status = vm.indexingStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Button {
                        vm.indexAllNotes(notes: notes)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                            Text("Index All Notes")
                        }
                    }
                    .disabled(!vm.isModelLoaded || vm.isBusy || notes.isEmpty)
                    
                    Text("Generates embeddings for RAG-powered chat. Required for context-aware responses.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Instructions") {
                    Text("1. Connect iPhone to Mac/PC")
                    Text("2. Open Finder (or iTunes)")
                    Text("3. Go to 'Files' tab for Synaps Notes")
                    Text("4. Drag .gguf models here")
                    Text("5. Refresh list")
                }
                
                Button("Refresh Models") {
                    vm.modelManager.refreshModels()
                }
            }
            .navigationTitle("Settings")
        }
    }
}
