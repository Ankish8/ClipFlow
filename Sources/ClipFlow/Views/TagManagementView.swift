import SwiftUI
import ClipFlowCore
import ClipFlowAPI
import ClipFlowBackend

// MARK: - Color Helper Functions

private func colorHexToColor(_ hex: String) -> Color {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch hex.count {
    case 3: // RGB (12-bit)
        (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6: // RGB (24-bit)
        (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8: // ARGB (32-bit)
        (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default:
        return Color.gray
    }
    
    return Color(
        red: Double(r) / 255,
        green: Double(g) / 255,
        blue: Double(b) / 255,
        opacity: Double(a) / 255
    )
}

// MARK: - Tag Chip View

struct TagChipView: View {
    let tag: Tag
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: (() -> Void)?
    
    @State private var isHovered = false
    
    init(tag: Tag, isSelected: Bool = false, onTap: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.tag = tag
        self.isSelected = isSelected
        self.onTap = onTap
        self.onDelete = onDelete
    }
    
    var body: some View {
        HStack(spacing: 4) {
            // Icon
            Image(systemName: tag.icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(foregroundColor)
            
            // Tag name
            Text(tag.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(foregroundColor)
            
            // Delete button (optional)
            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(backgroundColor)
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(isHovered ? 1.0 : 0.0)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovered = hovering
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? selectedBackgroundColor : backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? selectedBorderColor : borderColor, lineWidth: isSelected ? 2 : 1)
                )
        )
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private var backgroundColor: SwiftUI.Color {
        let tagColor = TagColor(hex: tag.color) ?? TagColor(red: 0, green: 0, blue: 1)
        return SwiftUI.Color(red: tagColor.red, green: tagColor.green, blue: tagColor.blue)
    }
    
    private var foregroundColor: SwiftUI.Color {
        // Ensure text is readable on the background
        let tagColor = TagColor(hex: tag.color) ?? TagColor(red: 0, green: 0, blue: 1)
        let red = tagColor.red
        let green = tagColor.green
        let blue = tagColor.blue
        let luminance = (0.299 * red * 255 + 0.587 * green * 255 + 0.114 * blue * 255) / 255
        return luminance > 0.5 ? SwiftUI.Color.black : SwiftUI.Color.white
    }
    
    private var selectedBackgroundColor: SwiftUI.Color {
        backgroundColor.opacity(0.9)
    }
    
    private var selectedBorderColor: SwiftUI.Color {
        SwiftUI.Color.accentColor
    }
    
    private var borderColor: SwiftUI.Color {
        backgroundColor.opacity(0.3)
    }
}

// MARK: - Tag Creation View

struct TagCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tagName = ""
    @State private var selectedColor = "#007AFF"
    @State private var selectedIcon = "tag.fill"
    @State private var tagDescription = ""
    
    let onCreateTag: (String, String, String, String?) -> Void
    
    // Predefined colors
    private let colors = [
        "#007AFF", "#FF3B30", "#34C759", "#FF9500",
        "#5856D6", "#AF52DE", "#FF2D92", "#8E8E93"
    ]
    
    // Predefined icons
    private let icons = [
        "tag.fill", "star.fill", "heart.fill", "bookmark.fill",
        "flag.fill", "pin.fill", "bell.fill", "lightbulb.fill",
        "briefcase.fill", "person.fill", "house.fill", "car.fill",
        "gamecontroller.fill", "headphones", "camera.fill", "photo.fill"
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Create New Tag")
                .font(.title2.weight(.semibold))
                .foregroundColor(.primary)
            
            // Tag name
            VStack(alignment: .leading, spacing: 8) {
                Text("Tag Name")
                    .font(.headline.weight(.medium))
                    .foregroundColor(.primary)
                
                TextField("Enter tag name", text: $tagName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Color selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.headline.weight(.medium))
                    .foregroundColor(.primary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach(colors, id: \.self) { color in
                        Button(action: { selectedColor = color }) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorHexToColor(color))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedColor == color ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                                .frame(height: 32)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Icon selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.headline.weight(.medium))
                    .foregroundColor(.primary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Button(action: { selectedIcon = icon }) {
                                Image(systemName: icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(selectedIcon == icon ? Color.accentColor : .primary)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedIcon == icon ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            
            // Description (optional)
            VStack(alignment: .leading, spacing: 8) {
                Text("Description (Optional)")
                    .font(.headline.weight(.medium))
                    .foregroundColor(.primary)
                
                TextField("Optional description", text: $tagDescription, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3)
            }
            
            // Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.headline.weight(.medium))
                    .foregroundColor(.primary)
                
                TagChipView(
                    tag: Tag(
                        name: tagName.isEmpty ? "Tag Name" : tagName,
                        color: selectedColor,
                        icon: selectedIcon,
                        description: tagDescription.isEmpty ? nil : tagDescription
                    )
                ) {}
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("Create Tag") {
                    if !tagName.isEmpty {
                        onCreateTag(tagName, selectedColor, selectedIcon, tagDescription.isEmpty ? nil : tagDescription)
                        dismiss()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(tagName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Tag Management View

struct TagManagementView: View {
    @State private var tags: [Tag] = []
    @State private var showingCreateTag = false
    @State private var editingTag: Tag?
    @State private var showingEditTag = false
    @State private var selectedTag: Tag?
    @State private var showingDeleteAlert = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    private let clipboardService = ClipboardService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Tags")
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { showingCreateTag = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            // Tags list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tags, id: \.id) { tag in
                        TagRowView(
                            tag: tag,
                            onEdit: {
                                editingTag = tag
                                showingEditTag = true
                            },
                            onDelete: {
                                selectedTag = tag
                                showingDeleteAlert = true
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showingCreateTag) {
            TagCreationView { name, color, icon, description in
                createTag(name: name, color: color, icon: icon, description: description)
            }
        }
        .sheet(isPresented: $showingEditTag) {
            if let tag = editingTag {
                TagCreationView { name, color, icon, description in
                    updateTag(tag, name: name, color: color, icon: icon, description: description)
                }
            }
        }
        .onAppear {
            loadTags()
        }
        .onAppear {
            loadTags()
        }
    }
    
    private func loadTags() {
        Task {
            do {
                tags = try await clipboardService.getAllTags()
            } catch {
                errorMessage = "Failed to load tags: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
    
    private func createTag(name: String, color: String, icon: String, description: String?) {
        Task {
            do {
                let tag = Tag(name: name, color: color, icon: icon, description: description)
                _ = try await clipboardService.createTag(tag)
                await MainActor.run {
                    loadTags()
                }
            } catch {
                errorMessage = "Failed to create tag: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
    
    private func updateTag(_ tag: Tag, name: String, color: String, icon: String, description: String?) {
        Task {
            do {
                var updatedTag = tag
                updatedTag.updateMetadata(name: name, color: color, icon: icon, description: description)
                try await clipboardService.updateTag(updatedTag)
                await MainActor.run {
                    loadTags()
                }
            } catch {
                errorMessage = "Failed to update tag: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
    
    private func deleteTag(_ tag: Tag) {
        Task {
            do {
                try await clipboardService.deleteTag(id: tag.id)
                await MainActor.run {
                    loadTags()
                }
            } catch {
                errorMessage = "Failed to delete tag: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

// MARK: - Tag Row View

struct TagRowView: View {
    let tag: Tag
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Tag icon
            Image(systemName: tag.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colorHexToColor(tag.color))
                .frame(width: 24, height: 24)
            
            // Tag info
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                if let description = tag.description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Text("\(tag.usageCount) uses")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(isHovered ? 1.0 : 0.0)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(isHovered ? 1.0 : 0.0)
            }
            .opacity(isHovered ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.gray).opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.gray).opacity(0.4), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.accentColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}