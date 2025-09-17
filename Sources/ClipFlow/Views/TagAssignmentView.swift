import SwiftUI
import ClipFlowCore
import ClipFlowBackend
import ClipFlowAPI

struct TagAssignmentView: View {
    let item: ClipboardItem
    let onTagsChanged: (Set<String>) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @StateObject private var viewModel = TagAssignmentViewModel()
    @State private var selectedTags: Set<String>
    @State private var searchQuery = ""
    @State private var showingCreateTag = false
    
    init(item: ClipboardItem, onTagsChanged: @escaping (Set<String>) -> Void) {
        self.item = item
        self.onTagsChanged = onTagsChanged
        self._selectedTags = State(initialValue: item.tags)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Search
            searchView
            
            // Tags list
            tagsListView
            
            // Create new tag
            createTagView
            
            // Actions
            actionButtons
        }
        .frame(width: 350, height: 450)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .sheet(isPresented: $showingCreateTag) {
            CreateEditTagView(tag: nil) { tag in
                Task {
                    await viewModel.createTag(tag)
                }
            }
        }
        .onAppear {
            viewModel.loadTags()
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Assign Tags")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    private var searchView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
            
            TextField("Search tags...", text: $searchQuery)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
    
    private var tagsListView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filteredTags) { tag in
                    TagSelectionRow(
                        tag: tag,
                        isSelected: selectedTags.contains(tag.name),
                        onToggle: { isSelected in
                            if isSelected {
                                selectedTags.insert(tag.name)
                            } else {
                                selectedTags.remove(tag.name)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var createTagView: some View {
        HStack {
            Button(action: {
                showingCreateTag = true
            }) {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                    Text("Create New Tag")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text("Cancel")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            Button(action: saveTags) {
                Text("Save")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    private var filteredTags: [Tag] {
        if searchQuery.isEmpty {
            return viewModel.tags
        } else {
            return viewModel.tags.filter { tag in
                tag.name.lowercased().contains(searchQuery.lowercased()) ||
                tag.description?.lowercased().contains(searchQuery.lowercased()) == true
            }
        }
    }
    
    private func saveTags() {
        onTagsChanged(selectedTags)
        presentationMode.wrappedValue.dismiss()
    }
}

struct TagSelectionRow: View {
    let tag: Tag
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: {
                onToggle(!isSelected)
            }) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? tag.colorValue : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Tag color indicator
            Circle()
                .fill(tag.colorValue)
                .frame(width: 10, height: 10)
            
            // Tag icon
            if let icon = tag.icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(tag.colorValue)
            }
            
            // Tag name
            Text(tag.name)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Item count
            Text("\(tag.itemCount)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? tag.colorValue.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? tag.colorValue : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        
    }
}

// MARK: - ViewModel

@MainActor
class TagAssignmentViewModel: ObservableObject {
    @Published private(set) var tags: [Tag] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    
    private let clipboardService = ClipboardService.shared
    
    func loadTags() {
        Task {
            await fetchTags()
        }
    }
    
    func fetchTags() async {
        isLoading = true
        error = nil
        
        do {
            tags = try await clipboardService.getAllTags()
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func createTag(_ tag: Tag) async {
        do {
            let createdTag = try await clipboardService.createTag(
                name: tag.name,
                color: tag.color,
                icon: tag.icon,
                description: tag.description
            )
            tags.append(createdTag)
        } catch {
            self.error = error.localizedDescription
        }
    }
}