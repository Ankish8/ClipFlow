import SwiftUI
import ClipFlowCore
import ClipFlowBackend

/// Inline tag creator - plus button that expands to text field
struct InlineTagCreator: View {
    @State private var isCreating = false
    @State private var tagName = ""
    @State private var selectedColor: TagColor = .blue
    @State private var showColorPicker = false
    @State private var showError = false
    @State private var errorMessage = ""

    let onTagCreated: (Tag) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        if isCreating {
            creationView
        } else {
            plusButton
        }
    }

    // MARK: - Plus Button

    private var plusButton: some View {
        Button(action: startCreating) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12, weight: .medium))

                Text("New Tag")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.toolbarChip())
    }

    // MARK: - Creation View

    private var creationView: some View {
        HStack(spacing: 6) {
            // Color indicator button
            Button(action: {
                showColorPicker.toggle()
            }) {
                Circle()
                    .fill(selectedColor.swiftUIColor)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.glass(.regular.tint(selectedColor.swiftUIColor)))
            .popover(isPresented: $showColorPicker) {
                TagColorPicker(selectedColor: $selectedColor)
                    .frame(width: 200)
            }

            // Text field
            TextField("Tag name", text: $tagName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isTextFieldFocused)
                .onSubmit {
                    NSLog("📝 Tag creator: onSubmit triggered")
                    createTag()
                }
                .onChange(of: tagName) { _, newValue in
                    NSLog("📝 Tag creator: Text changed to '\(newValue)'")
                    // Clear error when user starts typing
                    if showError {
                        withAnimation {
                            showError = false
                            errorMessage = ""
                        }
                    }
                }
                .onChange(of: isTextFieldFocused) { _, isFocused in
                    NSLog("📝 Tag creator: Focus changed to \(isFocused)")
                }
                .onKeyPress(.escape) {
                    NSLog("📝 Tag creator: Escape pressed")
                    cancelCreation()
                    return .handled
                }
                .frame(minWidth: 80, maxWidth: 150)

            // Confirm button
            if !tagName.isEmpty {
                Button(action: createTag) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
            }

            // Cancel button
            Button(action: cancelCreation) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(
            showError ? .regular.tint(.red.opacity(0.3)).interactive() : .regular.tint(Color.accentColor.opacity(0.15)).interactive(),
            in: .capsule
        )
        .modifier(ShakeEffect(shakes: showError ? 2 : 0))
        .onAppear {
            isTextFieldFocused = true
            // Optionally use random color
            if TagService.shared.getUseRandomColors() {
                selectedColor = TagColor.random()
            }
        }
    }

    // MARK: - Actions

    private func startCreating() {
        NSLog("📝 Tag creator: Starting creation mode")
        withAnimation(.easeInOut(duration: 0.2)) {
            isCreating = true
        }
    }

    private func cancelCreation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isCreating = false
            tagName = ""
            selectedColor = .blue
        }
    }

    private func createTag() {
        NSLog("📝 Tag creator: createTag() called with tagName='\(tagName)'")
        let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        NSLog("📝 Tag creator: Trimmed name='\(trimmedName)'")

        guard !trimmedName.isEmpty else {
            NSLog("📝 Tag creator: Name is empty, staying focused")
            return  // Just stay focused, don't close
        }

        // Validate tag name length
        guard trimmedName.count <= 30 else {
            withAnimation {
                showError = true
                errorMessage = "Tag name too long (max 30 characters)"
            }
            // Reset error after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    showError = false
                    errorMessage = ""
                }
            }
            return
        }

        // Check if tag already exists
        NSLog("📝 Tag creator: Checking if tag exists...")
        if TagService.shared.tagExists(name: trimmedName) {
            withAnimation {
                showError = true
                errorMessage = "Tag '\(trimmedName)' already exists"
            }
            NSLog("⚠️ Tag '\(trimmedName)' already exists")

            // Reset error after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    showError = false
                    errorMessage = ""
                }
            }
            return
        }

        // Create tag via service
        NSLog("📝 Tag creator: Creating tag '\(trimmedName)' with color \(selectedColor.displayName)...")
        Task {
            do {
                let newTag = try await TagService.shared.createTag(name: trimmedName, color: selectedColor)
                NSLog("✅ Tag creator: Tag created successfully: \(newTag.name)")
                onTagCreated(newTag)

                // Reset state
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCreating = false
                        tagName = ""
                        selectedColor = TagService.shared.getUseRandomColors() ? TagColor.random() : .blue
                        showError = false
                        errorMessage = ""
                    }
                }
            } catch {
                NSLog("❌ Failed to create tag: \(error)")
                await MainActor.run {
                    withAnimation {
                        showError = true
                        errorMessage = "Failed to create tag"
                    }

                    // Reset error after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation {
                            showError = false
                            errorMessage = ""
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Shake Effect

struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat = 0

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: 10 * sin(shakes * .pi * 2),
                y: 0
            )
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        InlineTagCreator { tag in
            print("Created tag: \(tag.name)")
        }

        // Show in different states
        HStack {
            InlineTagCreator { _ in }
        }
    }
    .padding()
    .frame(width: 400)
}
