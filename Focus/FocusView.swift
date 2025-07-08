import SwiftUI

// MARK: - Data Model
struct TaskItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var importance: Double // Scale of 1 to 10
    var urgency: Double    // Scale of 1 to 10
}

// MARK: - Custom Colors
extension Color {
    static let eisenhowerRed = Color(red: 192/255, green: 57/255, blue: 43/255)
    static let eisenhowerOrange = Color(red: 230/255, green: 126/255, blue: 34/255)
    static let eisenhowerGreen = Color(red: 39/255, green: 174/255, blue: 96/255)
    static let eisenhowerGrey = Color(red: 127/255, green: 140/255, blue: 141/255)
}

// MARK: - Groq API Networking Layer
enum APIError: Error, LocalizedError {
    case missingAPIKey, invalidURL, requestFailed(Error), decodingFailed(Error), noContent
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API Key is missing. Check your Secrets.plist for a key named 'GroqAPIKey'."
        case .invalidURL: return "The API endpoint URL is invalid."
        case .requestFailed: return "The network request failed. Check your connection."
        case .decodingFailed(let error): return "Failed to process the server response. Details: \(error.localizedDescription)"
        case .noContent: return "The AI returned no content. Please try again."
        }
    }
}

struct Secrets {
    static var apiKey: String {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let secrets = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return "" }
        return secrets["GroqAPIKey"] as? String ?? ""
    }
}

struct GroqRequest: Codable { let messages: [Message]; let model: String }
struct Message: Codable { let role: String; let content: String }
struct GroqResponse: Codable { let choices: [Choice] }
struct Choice: Codable { let message: ResponseMessage }
struct ResponseMessage: Codable { let role: String; let content: String }

class AIService {
    private static let groqAPIEndpoint = "https://api.groq.com/openai/v1/chat/completions"
    
    static func getStrategicSummary(for tasks: [TaskItem]) async throws -> String {
        let apiKey = Secrets.apiKey; guard !apiKey.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: groqAPIEndpoint) else { throw APIError.invalidURL }
        let doTasks = tasks.filter { $0.importance > 5 && $0.urgency > 5 }.map { $0.name }
        let planTasks = tasks.filter { $0.importance > 5 && $0.urgency <= 5 }.map { $0.name }
        let systemPrompt = "You are FocusAI, a productivity strategist. Analyze the user's task list based on the Eisenhower Matrix. Your response MUST be a powerful, concise summary of their strategic position. It must be 30 words or less. Do not use pleasantries, markdown, or extra text."
        let userPrompt = "My urgent & important tasks are: \(doTasks.isEmpty ? "None" : doTasks.joined(separator: ", ")). My important but not urgent tasks are: \(planTasks.isEmpty ? "None" : planTasks.joined(separator: ", ")). Give me a direct, strategic summary."
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(GroqRequest(messages: [Message(role: "system", content: systemPrompt), Message(role: "user", content: userPrompt)], model: "llama3-8b-8192"))
        do { let (data, _) = try await URLSession.shared.data(for: request); let response = try JSONDecoder().decode(GroqResponse.self, from: data); guard let content = response.choices.first?.message.content else { throw APIError.noContent }; return content } catch let urlError as URLError { throw APIError.requestFailed(urlError) } catch { throw APIError.decodingFailed(error) }
    }
}

// MARK: - Main View
struct FocusView: View {
    @State private var tasks: [TaskItem] = []
    @State private var selectedTask: TaskItem?
    @State private var showAISummarySheet = false
    @State private var showTaskListView = false
    @State private var aiSummary: String?
    @State private var isFetchingSummary = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                EisenhowerMatrixView(tasks: tasks, selectedTask: $selectedTask).padding()
                TaskInputView(tasks: $tasks)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("FOCUS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button(action: fetchAISummary) { Label("AI Insights", systemImage: "sparkles") }.disabled(tasks.isEmpty) }
                ToolbarItem(placement: .navigationBarTrailing) { Button { showTaskListView = true } label: { Label("All Tasks", systemImage: "list.bullet") }.disabled(tasks.isEmpty) }
            }
            .sheet(isPresented: $showAISummarySheet) { AISummaryView(summary: $aiSummary, isLoading: $isFetchingSummary) }
            .sheet(item: $selectedTask) { task in TaskDetailView(task: task) { deleteTask(withId: task.id) } }
            .sheet(isPresented: $showTaskListView) { TaskListView(tasks: $tasks, selectedTask: $selectedTask, isPresented: $showTaskListView) }
        }
    }
    private func fetchAISummary() { isFetchingSummary = true; aiSummary = nil; showAISummarySheet = true; Task { do { let summary = try await AIService.getStrategicSummary(for: tasks); await MainActor.run { self.aiSummary = summary; self.isFetchingSummary = false } } catch { await MainActor.run { self.aiSummary = "Error: \(error.localizedDescription)"; self.isFetchingSummary = false } } } }
    private func deleteTask(withId id: UUID) { tasks.removeAll { $0.id == id } }
}

// MARK: - Task List View
struct TaskListView: View {
    @Binding var tasks: [TaskItem]; @Binding var selectedTask: TaskItem?; @Binding var isPresented: Bool
    var body: some View { NavigationView { Group { if tasks.isEmpty { Text("No tasks yet.").foregroundColor(.secondary) } else { List { ForEach(tasks) { task in VStack(alignment: .leading, spacing: 4) { Text(task.name).fontWeight(.medium); Text("Importance: \(Int(task.importance))/10 ・ Urgency: \(Int(task.urgency))/10").font(.caption).foregroundColor(.secondary) }.padding(.vertical, 4).contentShape(Rectangle()).onTapGesture { selectedTask = task; isPresented = false } }.onDelete(perform: deleteTask) } } }.navigationTitle("All Tasks").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { isPresented = false } }; ToolbarItem(placement: .navigationBarLeading) { EditButton() } } } }
    private func deleteTask(at offsets: IndexSet) { tasks.remove(atOffsets: offsets) }
}

// MARK: - Eisenhower Matrix (Re-architected for Accurate Plotting)
struct EisenhowerMatrixView: View {
    let tasks: [TaskItem]
    @Binding var selectedTask: TaskItem?
    
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                Spacer().frame(width: 20); Text("URGENT").kerning(1.5).font(.caption.weight(.semibold)).foregroundColor(.secondary).frame(maxWidth: .infinity)
                Text("NOT URGENT").kerning(1.5).font(.caption.weight(.semibold)).foregroundColor(.secondary).frame(maxWidth: .infinity)
            }.padding(.bottom, 4)

            HStack(spacing: 3) {
                VStack(spacing: 3) {
                    ZStack { Text("Important").font(.callout.weight(.medium)).foregroundColor(.secondary).rotationEffect(.degrees(-90)).fixedSize() }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    ZStack { Text("Not Important").font(.callout.weight(.medium)).foregroundColor(.secondary).rotationEffect(.degrees(-90)).fixedSize() }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(width: 20)
                
                // --- CORE CHANGE: ZStack for background grid and foreground plot ---
                ZStack {
                    // Layer 1: The visual grid of quadrants (now without plotting logic)
                    VStack(spacing: 3) {
                        HStack(spacing: 3) {
                            QuadrantView(title: "DO", subtitle: "immediately", color: .eisenhowerRed, iconName: "checkmark")
                            QuadrantView(title: "PLAN", subtitle: "and prioritize", color: .eisenhowerOrange, iconName: "clock")
                        }
                        HStack(spacing: 3) {
                            QuadrantView(title: "DELEGATE", subtitle: "for completion", color: .eisenhowerGreen, iconName: "arrow.right")
                            QuadrantView(title: "DELETE", subtitle: "these tasks", color: .eisenhowerGrey, iconName: "xmark")
                        }
                    }
                    
                    // Layer 2: A single GeometryReader for plotting ALL tasks accurately
                    GeometryReader { geo in
                        ForEach(tasks) { task in
                            Circle().fill(.white)
                                .frame(width: 14, height: 14)
                                .shadow(color: .black.opacity(0.2), radius: 2)
                                .position(
                                    // Urgency (1-10) on X-axis. A value of 1 is on the left, 10 is on the right.
                                    x: (1 - (task.urgency - 1) / 9) * geo.size.width,
                                    // Importance (1-10) on Y-axis. A value of 1 is at the bottom, 10 is at the top.
                                    y: (1 - (task.importance - 1) / 9) * geo.size.height
                                )
                                .onTapGesture { self.selectedTask = task }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Quadrant View (Simplified: Now just a visual component)
struct QuadrantView: View {
    let title: String
    let subtitle: String
    let color: Color
    let iconName: String
    
    var body: some View {
        ZStack {
            color
            Image(systemName: iconName).font(.system(size: 80, weight: .light)).foregroundColor(.white.opacity(0.15))
            
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.body)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Task Input and Detail Views
struct TaskInputView: View {
    @Binding var tasks: [TaskItem]
    @State private var newTaskName: String = ""
    @State private var newImportance: Double = 5.5
    @State private var newUrgency: Double = 5.5
    var body: some View {
        Form {
            Section(header: Text("Add a New Task")) {
                TextField("Task Name (e.g., 'File quarterly taxes')", text: $newTaskName)
                VStack { HStack { Text("Importance"); Spacer(); Text("\(newImportance, specifier: "%.1f") / 10").foregroundColor(.secondary) }; Slider(value: $newImportance, in: 1...10, step: 0.5) }
                VStack { HStack { Text("Urgency"); Spacer(); Text("\(newUrgency, specifier: "%.1f") / 10").foregroundColor(.secondary) }; Slider(value: $newUrgency, in: 1...10, step: 0.5) }
                Button(action: addTask) { HStack { Spacer(); Image(systemName: "plus.circle.fill"); Text("Plot Task"); Spacer() } }.disabled(newTaskName.isEmpty)
            }
        }.frame(height: 320)
    }
    private func addTask() {
        guard !newTaskName.isEmpty else { return }; let newTask = TaskItem(name: newTaskName, importance: newImportance, urgency: newUrgency); withAnimation(.spring()) { tasks.append(newTask) }
        newTaskName = ""; newImportance = 5.5; newUrgency = 5.5; UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
struct AISummaryView: View {
    @Binding var summary: String?; @Binding var isLoading: Bool; @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading { HStack(spacing: 15) { ProgressView(); Text("FocusAI is analyzing...") }.padding() } else if let summary = summary { Text(summary).font(.title3).fontWeight(.medium).multilineTextAlignment(.leading).padding() }
                Spacer()
            }.navigationTitle("AI Summary").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }.presentationDetents([.height(200)])
    }
}

struct TaskDetailView: View {
    let task: TaskItem; var onDelete: () -> Void; @Environment(\.dismiss) var dismiss; @State private var showConfirmDelete = false
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text(task.name).font(.largeTitle).fontWeight(.bold)
                HStack {
                    VStack(alignment: .leading) { Text("Importance").font(.headline).foregroundColor(.secondary); Text("\(task.importance, specifier: "%.1f") / 10").font(.title2).fontWeight(.semibold) }
                    Spacer()
                    VStack(alignment: .leading) { Text("Urgency").font(.headline).foregroundColor(.secondary); Text("\(task.urgency, specifier: "%.1f") / 10").font(.title2).fontWeight(.semibold) }
                }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(12)
                Spacer()
            }
            .padding()
            .navigationTitle("Task Details").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button(role: .destructive) { showConfirmDelete = true } label: { Image(systemName: "trash") } }
            }
            .confirmationDialog("Delete this task?", isPresented: $showConfirmDelete, titleVisibility: .visible) { Button("Delete Task", role: .destructive) { onDelete(); dismiss() } } message: { Text("This action cannot be undone.") }
        }
        .presentationDetents([.height(300)])
    }
}

struct FocusView_Previews: PreviewProvider {
    static var previews: some View {
        FocusView()
    }
}
