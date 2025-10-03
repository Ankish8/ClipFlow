import SwiftUI
import ClipFlowCore
import ClipFlowAPI

struct TagAssignmentView: View {
    let item: ClipboardItem
    let availableTags: [Tag]
    let currentTags: [Tag]
    let onTagAssigned: (Tag) -> Void
    let onTagRemoved: (Tag) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedTag: Tag?
    
    var filteredTags: [Tag] {
        if searchText.isEmpty {
            return availableTags
        } else {
            return availableTags.filter { tag in
                tag.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Manage Tags")
                .font(.title2.weight(.semibold))
                .foregroundColor(.primary)
            
            Text("Item: \(item.content.displayText)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search tags...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            Divider()
            
            // Current tags
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Tags")
                    .font(.headline.weight(.medium))
                    .foregroundColor(.primary)
                
                if currentTags.isEmpty {
                    Text("No tags assigned")
                        .font(.body)
                        .foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                        ForEach(currentTags, id: \.id) { tag in
                            TagChipView(
                                tag: tag,
                                isSelected: true,
                                onTap: {},
                                onDelete: {
                                    onTagRemoved(tag)
                                }
                            )
                        }
                    }
                }
            }
            
            Divider()
            
            // Available tags
            VStack(alignment: .leading, spacing: 8) {
                Text("Available Tags")
                    .font(.headline.weight(.medium))
                    .foregroundColor(.primary)
                
                if filteredTags.isEmpty {
                    Text("No tags available")
                        .font(.body)
                        .foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                        ForEach(filteredTags.filter { tag in !currentTags.contains(where: { $0.id == tag.id }) }, id: \.id) { tag in
                            TagChipView(
                                tag: tag,
                                isSelected: false
                            ) {
                                onTagAssigned(tag)
                            }
                        }
                    }
                }
            }
            
            // Create new tag button
            Button(action: {
                // Handle creating new tag (for now, just show placeholder)
            }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Create New Tag")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding()
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Done button
            Button("Done") {
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .frame(width: 450, height: 600)
        .background(Color.secondary.opacity(0.1))
    }
}