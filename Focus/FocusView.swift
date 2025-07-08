import SwiftUI

// MARK: - Data Model
struct TaskItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var effort: Double // Scale of 1 to 10
    var impact: Double // Scale of 1 to 10
}

// MARK: - AI Service (Placeholder)
// In a real app, this would make a network request to an LLM API.
class AIService {
    
    // This is the core AI function for this feature.
    static func getStrategicSummary(for tasks: [TaskItem], completion: @escaping (Result<String, Error>) -> Void) {
        
        // 1. Categorize tasks for the AI prompt
        let quickWins = tasks.filter { $0.impact > 5 && $0.effort <= 5 }
        let majorProjects = tasks.filter { $0.impact > 5 && $0.effort > 5 }
        let fillIns = tasks.filter { $0.impact <= 5 && $0.effort <= 5 }
        let thanklessTasks = tasks.filter { $0.impact <= 5 && $0.effort > 5 }
        
        // 2. Build a detailed prompt for the LLM
        let prompt = """
        You are a world-class productivity coach and strategic advisor. Analyze the following list of tasks, which have been categorized into an Eisenhower Matrix.
        
        **Matrix Snapshot:**
        - **Quick Wins (High Impact, Low Effort):** \(quickWins.count) tasks. \(quickWins.map { $0.name }.joined(separator: ", "))
        - **Major Projects (High Impact, High Effort):** \(majorProjects.count) tasks. \(majorProjects.map { $0.name }.joined(separator: ", "))
        - **Fill-ins (Low Impact, Low Effort):** \(fillIns.count) tasks. \(fillIns.map { $0.name }.joined(separator: ", "))
        - **Thankless Tasks (Low Impact, High Effort):** \(thanklessTasks.count) tasks. \(thanklessTasks.map { $0.name }.joined(separator: ", "))

        **Your Task:**
        Provide a concise, actionable summary based on this distribution.
        1. Start with a brief, encouraging overview of the current situation.
        2. Provide 2-3 specific, bulleted recommendations on what to focus on or what to change.
        3. Keep the tone professional, insightful, and motivating.
        4. Format your response using markdown.
        """
        
        print("--- Sending Prompt to AI ---")
        print(prompt)
        print("--------------------------")
        
        // 3. Simulate network delay and a realistic LLM response
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            
            // This is a mocked response. A real LLM would generate this dynamically.
            let mockSummary = """
            ### Strategic Summary
            
            You have a solid overview of your priorities. Your focus is spread across several key areas, which is a good start. Let's sharpen that focus.
            
            **Key Recommendations:**
            
            *   **Capitalize on Quick Wins:** You have **\(quickWins.count) high-impact, low-effort tasks**. Tackle these first to build momentum and deliver immediate value. Start with **"\(quickWins.first?.name ?? "your top quick win")"**.
            
            *   **Plan Your Major Projects:** Your **\(majorProjects.count) major projects** are crucial for long-term success. Choose one to be your primary focus and break it down into smaller, more manageable steps. Don't try to do them all at once.
            
            *   **Delegate or Defer:** The **\(thanklessTasks.count) thankless tasks** are a potential energy drain. Scrutinize these carefully. Can they be delegated, automated, or eliminated entirely? They are actively pulling you away from high-impact work.
            
            Keep up the great work. A clear plan is the first step to outstanding results.
            """
            
            completion(.success(mockSummary))
        }
    }
}


// MARK: - Main View
struct FocusView: View {
    
    // MARK: State Management
    @State private var tasks: [TaskItem] = [
        .init(name: "Design new app icon", effort: 3, impact: 8),
        .init(name: "Refactor database schema", effort: 9, impact: 9),
        .init(name: "Write weekly blog post", effort: 4, impact: 6),
        .init(name: "Fix minor UI bug", effort: 1, impact: 4),
        .init(name: "Organize team meeting", effort: 2, impact: 2),
        .init(name: "Research Q4 strategy", effort: 10, impact: 10),
        .init(name: "Update dependencies", effort: 6, impact: 3),
        .init(name: "Answer support emails", effort: 7, impact: 4)
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
                // AI INSIGHTS BUTTON
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: fetchAISummary) {
                        Label("AI Insights", systemImage: "sparkles")
                    }
                }
            }
            // Sheet for AI Summary
            .sheet(isPresented: $showAISummarySheet) {
                AISummaryView(summary: $aiSummary, isLoading: $isFetchingSummary)
            }
            // Sheet to show task details
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
            }
        }
    }
    
    // Function to trigger the AI analysis
    private func fetchAISummary() {
        isFetchingSummary = true
        aiSummary = nil // Clear previous summary
        showAISummarySheet = true // Show the sheet immediately with loading indicator
        
        AIService.getStrategicSummary(for: tasks) { result in
            switch result {
            case .success(let summary):
                self.aiSummary = summary
            case .failure(let error):
                self.aiSummary = "An error occurred: \(error.localizedDescription)"
            }
            isFetchingSummary = false
        }
    }
}

// MARK: - AI Summary View (for the sheet)
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
                    Text("AI is analyzing your tasks...")
                        .foregroundColor(.secondary)
                } else if let summary = summary {
                    // Use AttributedString to render markdown
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
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        // Recommended sheet size
        .presentationDetents([.medium, .large])
    }
}


// MARK: - Eisenhower Matrix View
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

// MARK: - Quadrant View
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

// MARK: - UI Components (Axis, Input, Detail)
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
