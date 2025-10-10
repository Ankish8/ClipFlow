#!/bin/bash

echo "🧪 Tag System Test Script"
echo "========================="
echo ""
echo "This script will help you test all tag fixes."
echo ""
echo "📋 Pre-Test Checklist:"
echo "1. Close ClipFlow if it's running (Command+Q from menu bar)"
echo "2. This will start the NEW compiled version with all fixes"
echo ""
read -p "Press ENTER to start ClipFlow..."

# Kill any existing instances
pkill -f "ClipFlow" 2>/dev/null

# Run the new build
echo "🚀 Starting ClipFlow with fixes..."
./.build/debug/ClipFlow &

# Wait for app to start
sleep 2

echo ""
echo "✅ ClipFlow is now running!"
echo ""
echo "🧪 TEST 1: Create a Tag"
echo "  1. Click 'New Tag' button"
echo "  2. Notice the color circle is 16×16 (nice and big)"
echo "  3. Type a name and press Enter"
echo "  4. Check if the color circle is STILL big (should be 10×10 - slightly smaller but still visible)"
echo ""
echo "🧪 TEST 2: Right-Click Context Menu"
echo "  1. Right-click on any tag"
echo "  2. Select 'Change Color'"
echo "  3. A color picker popover should appear"
echo "  4. Select a new color - it should save"
echo ""
echo "🧪 TEST 3: Rename Tag"
echo "  1. Right-click on any tag"
echo "  2. Select 'Rename Tag'"
echo "  3. An alert dialog should appear with a text field"
echo "  4. Type new name and click 'Save'"
echo ""
echo "🧪 TEST 4: Drag and Drop"
echo "  1. Open overlay (⌥⌘V)"
echo "  2. Drag a card"
echo "  3. Drop it on a tag"
echo "  4. Check Console.app for logs: '🎯 Starting drag' and '🏷️ Applying tag'"
echo ""
echo "🧪 TEST 5: Search Auto-Focus"
echo "  1. Open overlay (⌥⌘V)"
echo "  2. Immediately start typing (don't click anything)"
echo "  3. Search should auto-expand and start filtering"
echo ""
echo "📊 Watch Console.app for detailed logs of all operations"
echo ""
echo "Press Command+Q on ClipFlow menu bar icon to stop testing."
