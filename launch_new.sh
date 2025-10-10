#!/bin/bash

echo "🔧 ClipFlow - Testing New Build"
echo "================================"
echo ""

# Kill all instances
echo "🛑 Killing all ClipFlow instances..."
pkill -9 -f ClipFlow 2>/dev/null
sleep 1

# Launch new build
echo "🚀 Launching new ClipFlow build..."
./.build/debug/ClipFlow &

sleep 2

echo ""
echo "✅ ClipFlow is now running!"
echo ""
echo "📋 QUICK TEST GUIDE:"
echo ""
echo "1️⃣  INLINE RENAME:"
echo "    • Double-click any tag name"
echo "    • Type new name, press Enter"
echo "    • No modal - pure inline editing!"
echo ""
echo "2️⃣  COLOR PICKER:"
echo "    • Right-click tag → Change Color"
echo "    • Picker appears above tag"
echo "    • Click color → instant save"
echo ""
echo "3️⃣  DRAG & DROP:"
echo "    • Press ⌥⌘V (open overlay)"
echo "    • Drag a card onto a tag"
echo "    • Watch Console.app for logs:"
echo "      '🎯 DROP: TagChipView received'"
echo ""
echo "4️⃣  TAG REORDERING:"
echo "    • Create a few tags"
echo "    • Drag a tag left/right to reorder"
echo "    • Restart app - order persists!"
echo "    • New tags appear on rightmost side"
echo ""
echo "5️⃣  SEARCH AUTO-FOCUS:"
echo "    • Press ⌥⌘V (open overlay)"
echo "    • Immediately type (no clicking!)"
echo "    • Search expands instantly"
echo ""
echo "6️⃣  NO ANIMATIONS:"
echo "    • Click tags rapidly"
echo "    • Should feel instant/snappy"
echo ""
echo "📊 Open Console.app to see all debug logs"
echo "🛑 Press Command+Q on menu bar to quit"
echo ""
echo "All 6 features now complete! Report any issues with console log output!"
