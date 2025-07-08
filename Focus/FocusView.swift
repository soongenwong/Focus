import SwiftUI

// MARK: - Data Model
struct TaskItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var effort: Double // Scale of 1 to 10
    var impact: Double // Scale of 1 to 10
}

// MARK: - Secrets Management
// This struct safely loads the API key from the Secrets.plist file.
struct Secrets {
    static var groqApiKey: String? {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] else {
            return nil
        }
        return dict["GroqApiKey"] as? String
    }
}

// MARK: - Groq API Networking Layer

// Custom error for our API service
enum APIError: Error, LocalizedError {
    case missingApiKey
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case noData
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .missingApiKey: return "Groq API Key is missing. Please add it to Secrets.plist."
        case .invalidURL: return "The API endpoint URL is invalid."
        case .requestFailed: return "The network request failed."
        case .invalidResponse: return "Received an invalid response from the server."
        case .noData: return "No content was returned from the AI."
        case .decodingError: return "Failed to decode the server's response."
        }
    }
}

// Codable structs to match the Groq API JSON structure
struct GroqRequest: Codable {
    let messages: [ChatMessage]
    let model: String
    let temperature: Double
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct GroqResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: ChatMessage
}


// The updated AI Service to make real network calls
class AIService {
    
    private static let groqAPIEndpoint = "https://api.groq.com/openai/v4/chat/completions"
    
    // This is the core AI function. It's now async and can throw errors.
    static func getStrategicSummary(for tasks: [TaskItem]) async throws -> String {
        
        // 1. Ensure API Key exists
        guard let apiKey = Secrets.groqApiKey else {
            throw APIError.missingApiKey
        }
        
        // 2. Categorize tasks for the prompt
        let quickWins = tasks.filter { $0.impact > 5 && $0.effort <= 5 }
        let majorProjects = tasks.filter { $0.impact > 5 && $0.effort > 5 }
        let fillIns = tasks.filter { $0.impact <= 5 && $0.effort <= 5 }
        let thanklessTasks = tasks.filter { $0.impact <= 5 && $0.effort > 5 }
        
        // 3. Perfect the Prompt for Llama3
        // The system prompt sets the AI's persona and instructions.
        let systemPrompt = """
        You are FocusAI, a world-class productivity coach. Your tone is insightful, encouraging, and highly strategic.
        Analyze the user's task list from an Eisenhower Matrix. Provide a concise, actionable summary formatted in markdown.
        - Start with a sharp, one-sentence overview.
        - Use bullet points for 2-3 specific recommendations.
        - Focus on the *'why'* behind your advice (e.g., 'Tackle Quick Wins to build momentum').
        - Address the user directly ('You have...', 'Your focus should be...').
        """
        
        // The user prompt provides the data.
        let userPrompt = """
        Here is my current task distribution:
        - Quick Wins (High Impact, Low Effort): \(quickWins.count) tasks. Tasks: \(quickWins.map { $0.name }.joined(separator: ", "))
        - Major Projects (High Impact, High Effort): \(majorProjects.count) tasks. Tasks: \(majorProjects.map { $0.name }.joined(separator: ", "))
        - Fill-ins (Low Impact, Low Effort): \(fillIns.count) tasks. Tasks: \(fillIns.map { $0.name }.joined(separator: ", "))
        - Thankless Tasks (Low Impact, High Effort): \(thanklessTasks.count) tasks. Tasks: \(thanklessTasks.map { $0.name }.joined(separator: ", "))
        
        Give me your strategic analysis.
        """

        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: userPrompt)
        ]
        
        // 4. Build the Request
        let groqRequest = GroqRequest(messages: messages, model: "llama3-8b-8192", temperature: 0.7)
        
        guard let url = URL(string: groqAPIEndpoint) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(groqRequest)
        
        // 5. Execute the network call
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        // 6. Decode the response and return the content
        let decodedResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
        
        guard let content = decodedResponse.choices.first?.message.content else {
            throw APIError.noData
        }
        
        return content
    }
}


// MARK: - Main View
struct FocusView: View {
    
    // MARK: State Management
    @State private var tasks: [TaskItem] = [
        .init(name: "Launch marketing campaign", effort: 4, impact: 9),
        .init(name: "Overhaul user authentication", effort: 8, impact: 10),
        .init(name: "Respond to customer feedback", effort: 3, impact: 6),
        .init(name: "Clean up project file structure", effort: 2, impact: 2),
        .init(name: "Research competitor APIs", effort: 7, impact: 7),
        .init(name: "Deprecate old V1 API", effort: 9, impact: 5),
        .init(name: "Fix typo on landing page", effort: 1, impact: 3)
    ]
    
    @State private var selectedTask: TaskItem?
    
    // State for the AI Summary
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
            .navigationTitle("Strategic Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        // Trigger the async task
                        fetchAISummary()
                    }) {
                        Label("AI Insights", systemImage: "sparkles")
                    }
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
    
    // Updated to use modern async/await
    private func fetchAISummary() {
        isFetchingSummary = true
        aiSummary = nil
        showAISummarySheet = true
        
        Task {
            do {
                let summary = try await AIService.getStrategicSummary(for: tasks)
                // UI updates must be on the main thread
                await MainActor.run {
                    self.aiSummary = summary
                    self.isFetchingSummary = false
                }
            } catch {
                await MainActor.run {
                    // Display the specific error to the user
                    self.aiSummary = "### Error\n\n\(error.localizedDescription)"
                    self.isFetchingSummary = false
                }
            }
        }
    }
}

// MARK: - ALL OTHER SUB-VIEWS (Unchanged)
// (The rest of the file remains the same as the previous version)

struct AISummaryView: View {
    @Binding var summary: String?
    @Binding var isLoading: Bool
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("FocusAI is analyzing your tasks...")
                        .foregroundColor(.secondary)
                        .padding()
                } else if let summary = summary {
                    ScrollView {
                        Text(try! AttributedString(markdown: summary))
                            .padding()
                    }
                } else {
                    Text("No summary available.")
                }
                Spacer()
            }
            .navigationTitle("AI Strategic Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct EisenhowerMatrixView: View {
    let tasks: [TaskItem]
    @Binding var selectedTask: TaskItem?
    
    var quickWins: [TaskItem]     { tasks.filter { $0.impact > 5 && $0.effort <= 5 } }
    var majorProjects: [TaskItem] { tasks.filter { $0.impact > 5 && $0.effort > 5 } }
    var fillIns: [TaskItem]       { tasks.filter { $0.impact <= 5 && $0.effort <= 5 } }
    var thanklessTasks: [TaskItem]{ tasks.filter { $0.impact <= 5 && $0.effort > 5 } }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                QuadrantView(title: "Quick Wins", subtitle: "High Impact, Low Effort", tasks: quickWins, selectedTask: $selectedTask, color: .green, isHighlighted: true)
                QuadrantView(title: "Major Projects", subtitle: "High Impact, High Effort", tasks: majorProjects, selectedTask: $selectedTask, color: .blue)
            }
            HStack(spacing: 8) {
                QuadrantView(title: "Fill-ins", subtitle: "Low Impact, Low Effort", tasks: fillIns, selectedTask: $selectedTask, color: .orange)
                QuadrantView(title: "Thankless Tasks", subtitle: "Low Impact, High Effort", tasks: thanklessTasks, selectedTask: $selectedTask, color: .red)
            }
        }
        .overlay(XAxisLabel(), alignment: .bottom)
        .overlay(YAxisLabel(), alignment: .leading)
    }
}

struct QuadrantView: View {
    let title: String, subtitle: String, tasks: [TaskItem]
    @Binding var selectedTask: TaskItem?
    let color: Color
    var isHighlighted: Bool = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)).shadow(color: isHighlighted ? color.opacity(0.5) : .clear, radius: 10, x: 0, y: 0)
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text(title).font(.headline).foregroundColor(color)
                        Text(subtitle).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }.padding()
                GeometryReader { geo in
                    ZStack {
                        ForEach(tasks) { task in
                            Circle().fill(Color.primary.opacity(0.7)).frame(width: 12, height: 12)
                                .position(x: (task.effort - 0.5) / 10 * geo.size.width, y: (1 - ((task.impact - 0.5) / 10)) * geo.size.height)
                                .onTapGesture { self.selectedTask = task }
                        }
                    }
                }
            }
        }
    }
}

struct XAxisLabel: View {
    var body: some View { Text("Effort →").font(.caption).foregroundColor(.secondary).padding(.horizontal).offset(y: 20) }
}

struct YAxisLabel: View {
    var body: some View { Text("Impact →").font(.caption).foregroundColor(.secondary).rotationEffect(.degrees(-90)).offset(x: -20) }
}

struct TaskInputView: View {
    @Binding var tasks: [TaskItem]
    @State private var newTaskName: String = ""
    @State private var newEffort: Double = 5
    @State private var newImpact: Double = 5
    
    var body: some View {
        Form {
            Section(header: Text("Add a New Task")) {
                TextField("Task Name (e.g., 'Deploy to production')", text: $newTaskName)
                VStack {
                    HStack { Text("Effort"); Spacer(); Text("\(Int(newEffort)) / 10").foregroundColor(.secondary) }
                    Slider(value: $newEffort, in: 1...10, step: 1)
                }
                VStack {
                    HStack { Text("Impact"); Spacer(); Text("\(Int(newImpact)) / 10").foregroundColor(.secondary) }
                    Slider(value: $newImpact, in: 1...10, step: 1)
                }
                Button(action: addTask) {
                    HStack { Spacer(); Image(systemName: "plus.circle.fill"); Text("Plot Task"); Spacer() }
                }.disabled(newTaskName.isEmpty)
            }
        }.frame(height: 320)
    }
    
    private func addTask() {
        guard !newTaskName.isEmpty else { return }
        let newTask = TaskItem(name: newTaskName, effort: newEffort, impact: newImpact)
        withAnimation(.spring()) { tasks.append(newTask) }
        newTaskName = ""; newEffort = 5; newImpact = 5
        // Hide keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct TaskDetailView: View {
    let task: TaskItem
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(task.name).font(.largeTitle).fontWeight(.bold)
            HStack {
                VStack(alignment: .leading) { Text("Impact").font(.headline).foregroundColor(.secondary); Text("\(Int(task.impact)) / 10").font(.title2).fontWeight(.semibold) }
                Spacer()
                VStack(alignment: .leading) { Text("Effort").font(.headline).foregroundColor(.secondary); Text("\(Int(task.effort)) / 10").font(.title2).fontWeight(.semibold) }
            }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(12)
            Spacer()
        }.padding().presentationDetents([.height(200)])
    }
}

// MARK: - Preview
struct FocusView_Previews: PreviewProvider {
    static var previews: some View {
        FocusView()
    }
}
