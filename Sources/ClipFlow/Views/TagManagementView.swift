import SwiftUI
import ClipFlowCore
import ClipFlowBackend
import ClipFlowAPI

struct TagManagementView: View {
    @StateObject private var viewModel = TagManagementViewModel()
    @State private var showingCreateTag = false
    @State private var editingTag: Tag?
    @State private var searchQuery = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Search and Create
            searchAndCreateView
            
            // Tags List
            tagsListView
        }
        .frame(width: 400, height: 500)
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
        .sheet(item: $editingTag) { tag in
            CreateEditTagView(tag: tag) { updatedTag in
                Task {
                    await viewModel.updateTag(updatedTag)
                }
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Tags")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                showingCreateTag = true
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .help("Create new tag")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    private var searchAndCreateView: some View {
        HStack(spacing: 12) {
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
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
    
    private var tagsListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredTags) { tag in
                    TagRowView(
                        tag: tag,
                        onEdit: { editingTag = tag },
                        onDelete: {
                            Task {
                                await viewModel.deleteTag(tag.id)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
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
}

struct TagRowView: View {
    let tag: Tag
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Tag color indicator
            Circle()
                .fill(tag.colorValue)
                .frame(width: 12, height: 12)
            
            // Tag icon
            if let icon = tag.icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(tag.colorValue)
            }
            
            // Tag name and info
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                if let description = tag.description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Text("\(tag.itemCount) items")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Actions
            if isHovering {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Edit tag")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Delete tag")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

struct CreateEditTagView: View {
    let tag: Tag?
    let onSave: (Tag) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @State private var name = ""
    @State private var color = "#007AFF"
    @State private var icon = ""
    @State private var description = ""
    @State private var selectedIcon = ""
    
    private let availableIcons = [
        "star.fill", "heart.fill", "briefcase.fill", "person.fill",
        "exclamationmark.triangle.fill", "curlybraces", "paintbrush.fill",
        "magnifyingglass", "doc.fill", "link", "photo.fill",
        "text.alignleft", "clock.fill", "folder.fill", "tag.fill"
    ]
    
    private let colorOptions = [
        "#007AFF", "#34C759", "#FF3B30", "#FF9500", "#AF52DE",
        "#5AC8FA", "#FF2D92", "#30D158", "#FF9F0A", "#BF5AF2"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Form
            formView
            
            // Actions
            actionButtons
        }
        .frame(width: 350, height: 400)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .onAppear {
            if let tag = tag {
                name = tag.name
                color = tag.color
                icon = tag.icon ?? ""
                selectedIcon = tag.icon ?? ""
                description = tag.description ?? ""
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Text(tag == nil ? "Create Tag" : "Edit Tag")
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
    
    private var formView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("Tag name", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 14))
                }
                
                // Color
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                        ForEach(colorOptions, id: \.self) { colorOption in
                            Circle()
                                .fill(Color(hex: colorOption) ?? Color.blue)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: color == colorOption ? 2 : 0)
                                )
                                .onTapGesture {
                                    color = colorOption
                                }
                        }
                    }
                }
                
                // Icon
                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon (Optional)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                        ForEach(availableIcons, id: \.self) { iconOption in
                            Image(systemName: iconOption)
                                .font(.system(size: 16))
                                .foregroundColor(selectedIcon == iconOption ? Color.blue : .secondary)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedIcon == iconOption ? Color.blue.opacity(0.1) : Color.clear)
                                )
                                .onTapGesture {
                                    selectedIcon = iconOption
                                    icon = iconOption
                                }
                        }
                    }
                }
                
                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description (Optional)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $description)
                        .frame(height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
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
            
            Button(action: saveTag) {
                Text("Save")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(name.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    private func saveTag() {
        let finalTag = Tag(
            id: tag?.id ?? UUID(),
            name: name,
            color: color,
            icon: icon.isEmpty ? nil : icon,
            description: description.isEmpty ? nil : description,
            usageCount: tag?.usageCount ?? 0,
            itemIds: tag?.itemIds ?? [],
            createdAt: tag?.createdAt ?? Date(),
            modifiedAt: Date()
        )
        
        onSave(finalTag)
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - ViewModel

@MainActor
class TagManagementViewModel: ObservableObject {
    @Published private(set) var tags: [Tag] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    
    private let clipboardService = ClipboardService.shared
    
    init() {
        loadTags()
    }
    
    private func loadTags() {
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
    
    func updateTag(_ tag: Tag) async {
        do {
            let updatedTag = try await clipboardService.updateTag(
                id: tag.id,
                name: tag.name,
                color: tag.color,
                icon: tag.icon,
                description: tag.description
            )
            
            if let index = tags.firstIndex(where: { $0.id == tag.id }) {
                tags[index] = updatedTag
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func deleteTag(_ tagId: UUID) async {
        do {
            try await clipboardService.deleteTag(id: tagId)
            tags.removeAll { $0.id == tagId }
        } catch {
            self.error = error.localizedDescription
        }
    }
}