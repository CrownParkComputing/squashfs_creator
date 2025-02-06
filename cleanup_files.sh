#!/bin/bash

# Files to delete
files_to_delete=(
  "lib/widgets/wine_download_widget.dart"
  "lib/widgets/wine_prefix_creator.dart"
  "lib/widgets/wine_type_selector_dialog.dart"
  "lib/services/winetricks_service.dart"
  "lib/services/wine_installer.dart"
  "lib/services/wine_downloader.dart"
  "lib/services/wine_builds_service.dart"
  "lib/services/prefix_manager.dart"  # Replaced by wine_service.dart
)

# Check each file and delete if it exists
for file in "${files_to_delete[@]}"; do
  if [ -f "$file" ]; then
    echo "Deleting $file"
    rm "$file"
  else
    echo "File not found: $file"
  fi
done

# Also update imports in remaining files
files_to_update=(
  "lib/screens/home_screen.dart"
  "lib/screens/games_screen.dart"
  "lib/widgets/game_manager_widget.dart"
)

# Remove unused imports
for file in "${files_to_update[@]}"; do
  if [ -f "$file" ]; then
    echo "Updating imports in $file"
    # Remove imports of deleted files
    sed -i '/wine_download_widget/d' "$file"
    sed -i '/wine_prefix_creator/d' "$file"
    sed -i '/wine_type_selector_dialog/d' "$file"
    sed -i '/winetricks_service/d' "$file"
    sed -i '/wine_installer/d' "$file"
    sed -i '/wine_downloader/d' "$file"
    sed -i '/wine_builds_service/d' "$file"
    sed -i '/prefix_manager/d' "$file"
    # Add new import if needed
    sed -i '1i import '\''../services/wine_service.dart'\'';' "$file"
  fi
done

echo "Cleanup complete!" 