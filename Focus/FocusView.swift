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
        let apiKey = Secrets.apiKey
        guard !apiKey.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: groqAPIEndpoint) else { throw APIError.invalidURL }
        
        let doTasks = tasks.filter { $0.importance > 5 && $0.urgency > 5 }.map { $0.name }
        let planTasks = tasks.filter { $0.importance > 5 && $0.urgency <= 5 }.map { $0.name }
        
        let systemPrompt = """
        You are FocusAI, a productivity strategist. Analyze the user's task list based on the Eisenhower Matrix.
        Your response MUST be a powerful, concise summary of their strategic position.
        It must be 30 words or less. Do not use pleasantries, markdown, or extra text.
        """
        
        let userPrompt = """
        My urgent & important tasks are: \(doTasks.isEmpty ? "None" : doTasks.joined(separator: ", ")).
        My important but not urgent tasks are: \(planTasks.isEmpty ? "None" : planTasks.joined(separator: ", ")).
        Give me a direct, strategic summary.
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = GroqRequest(messages: [Message(role: "system", content: systemPrompt), Message(role: "user", content: userPrompt)], model: "llama3-8b-8192")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(GroqResponse.self, from: data)
            guard let content = response.choices.first?.message.content else { throw APIError.noContent }
            return content
        } catch let urlError as URLError {
            throw APIError.requestFailed(urlError)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }
}

// MARK: - Main View
struct FocusView: View {
    
    // CHANGE 2: Tasks array now starts empty for a blank canvas.
    @State private var tasks: [TaskItem] = []
    
    @State private var selectedTask: TaskItem?
    @State private var showAISummarySheet = false
    @State private var aiSummary: String?
    @State private var isFetchingSummary = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                EisenhowerMatrixView(tasks: tasks, selectedTask: $selectedTask)
                    .padding()
                
                TaskInputView(tasks: $tasks)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Eisenhower Matrix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: fetchAISummary) {
                        Label("AI Insights", systemImage: "sparkles")
                    }
                    .disabled(tasks.isEmpty) // Disable button if there are no tasks
                }
            }
            .sheet(isPresented: $showAISummarySheet) {
                AISummaryView(summary: $aiSummary, isLoading: $isFetchingSummary)
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
            }
        }
    }
    
    private func fetchAISummary() {
        isFetchingSummary = true; aiSummary = nil; showAISummarySheet = true
        Task {
            do {
                let summary = try await AIService.getStrategicSummary(for: tasks)
                await MainActor.run { self.aiSummary = summary; self.isFetchingSummary = false }
            } catch {
                await MainActor.run { self.aiSummary = "Error: \(error.localizedDescription)"; self.isFetchingSummary = false }
            }
        }
    }
}

// MARK: - UI Helper View for Vertical Text
// CHANGE 1: New View to render text vertically, character by character.
struct VerticalTextView: View {
    let text: String
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .kerning(1.5)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Eisenhower Matrix View
struct EisenhowerMatrixView: View {
    let tasks: [TaskItem]
    @Binding var selectedTask: TaskItem?
    
    var doTasks: [TaskItem]         { tasks.filter { $0.importance > 5 && $0.urgency > 5 } }
    var planTasks: [TaskItem]       { tasks.filter { $0.importance > 5 && $0.urgency <= 5 } }
    var delegateTasks: [TaskItem]   { tasks.filter { $0.importance <= 5 && $0.urgency > 5 } }
    var deleteTasks: [TaskItem]     { tasks.filter { $0.importance <= 5 && $0.urgency <= 5 } }
    
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                Spacer(minLength: 20)
                Text("URGENT").kerning(1.5).font(.caption.weight(.semibold)).foregroundColor(.secondary).frame(maxWidth: .infinity)
                Text("NOT URGENT").kerning(1.5).font(.caption.weight(.semibold)).foregroundColor(.secondary).frame(maxWidth: .infinity)
            }.padding(.bottom, 4)

            HStack(spacing: 3) {
                // CHANGE 1: Using the new VerticalTextView.
                VerticalTextView(text: "IMPORTANT")
                    .frame(width: 20)
                
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        QuadrantView(title: "DO", subtitle: "immediately", tasks: doTasks, selectedTask: $selectedTask, color: .eisenhowerRed, iconName: "checkmark")
                        QuadrantView(title: "PLAN", subtitle: "and prioritize", tasks: planTasks, selectedTask: $selectedTask, color: .eisenhowerOrange, iconName: "clock")
                    }
                    HStack(spacing: 3) {
                        QuadrantView(title: "DELEGATE", subtitle: "for completion", tasks: delegateTasks, selectedTask: $selectedTask, color: .eisenhowerGreen, iconName: "arrow.right")
                        QuadrantView(title: "DELETE", subtitle: "these tasks", tasks: deleteTasks, selectedTask: $selectedTask, color: .eisenhowerGrey, iconName: "xmark")
                    }
                }
            }
            
            HStack(spacing: 3) {
                // CHANGE 1: Using the new VerticalTextView.
                VerticalTextView(text: "NOT IMPORTANT")
                    .frame(width: 20)
                Spacer()
            }
            .offset(y: -135)
            .frame(maxHeight: 0)
        }
    }
}

// MARK: - Quadrant View
struct QuadrantView: View {
    let title: String, subtitle: String, tasks: [TaskItem]
    @Binding var selectedTask: TaskItem?
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

            GeometryReader { geo in
                ForEach(tasks) { task in
                    Circle().fill(.white)
                        // CHANGE 3: Increased frame size for larger dots.
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.2), radius: 2)
                        .position(
                            x: ((10.5 - task.urgency) / 10) * geo.size.width,
                            y: ((10.5 - task.importance) / 10) * geo.size.height
                        )
                        .onTapGesture { self.selectedTask = task }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Task Input and Detail Views
struct TaskInputView: View {
    @Binding var tasks: [TaskItem]
    @State private var newTaskName: String = ""
    @State private var newImportance: Double = 5
    @State private var newUrgency: Double = 5
    
    var body: some View {
        Form {
            Section(header: Text("Add a New Task")) {
                TextField("Task Name (e.g., 'File quarterly taxes')", text: $newTaskName)
                VStack {
                    HStack { Text("Importance"); Spacer(); Text("\(Int(newImportance)) / 10").foregroundColor(.secondary) }
                    Slider(value: $newImportance, in: 1...10, step: 1)
                }
                VStack {
                    HStack { Text("Urgency"); Spacer(); Text("\(Int(newUrgency)) / 10").foregroundColor(.secondary) }
                    Slider(value: $newUrgency, in: 1...10, step: 1)
                }
                Button(action: addTask) {
                    HStack { Spacer(); Image(systemName: "plus.circle.fill"); Text("Plot Task"); Spacer() }
                }.disabled(newTaskName.isEmpty)
            }
        }.frame(height: 320)
    }
    
    private func addTask() {
        guard !newTaskName.isEmpty else { return }
        let newTask = TaskItem(name: newTaskName, importance: newImportance, urgency: newUrgency)
        withAnimation(.spring()) { tasks.append(newTask) }
        newTaskName = ""; newImportance = 5; newUrgency = 5
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct AISummaryView: View {
    @Binding var summary: String?
    @Binding var isLoading: Bool
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    HStack(spacing: 15) { ProgressView(); Text("FocusAI is analyzing...") }.padding()
                } else if let summary = summary {
                    Text(summary).font(.title3).fontWeight(.medium).multilineTextAlignment(.leading).padding()
                }
                Spacer()
            }
            .navigationTitle("AI Summary").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.height(200)])
    }
}

struct TaskDetailView: View {
    let task: TaskItem
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(task.name).font(.largeTitle).fontWeight(.bold)
            HStack {
                VStack(alignment: .leading) { Text("Importance").font(.headline).foregroundColor(.secondary); Text("\(Int(task.importance)) / 10").font(.title2).fontWeight(.semibold) }
                Spacer()
                VStack(alignment: .leading) { Text("Urgency").font(.headline).foregroundColor(.secondary); Text("\(Int(task.urgency)) / 10").font(.title2).fontWeight(.semibold) }
            }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(12)
            Spacer()
        }.padding().presentationDetents([.height(200)])
    }
}

struct FocusView_Previews: PreviewProvider {
    static var previews: some View {
        FocusView()
    }
}
