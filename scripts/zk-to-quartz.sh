#!/bin/bash
# Export zk notes to Quartz format with improved link handling and recent notes update

# Directories
ZK_DIR="./notes"
QUARTZ_CONTENT_DIR="../website/content"
TEMPLATE_DIR=".zk/templates"

# Ensure Quartz content directory exists
mkdir -p "$QUARTZ_CONTENT_DIR"

# First pass: Extract titles from all notes and create a mapping file
echo "Building note ID to title mapping..."
MAPPING_FILE=$(mktemp)

find "$ZK_DIR" -name "*.md" | while read note_path; do
    # Skip if this is a template file
    if [[ "$note_path" == *"$TEMPLATE_DIR"* ]]; then
        continue
    fi
    
    note_filename=$(basename "$note_path")
    note_id="${note_filename%.md}"
    
    # Read the file
    content=$(cat "$note_path")
    
    # Extract title from frontmatter or first heading
    if [[ "$content" == ---* ]]; then
        title=$(echo "$content" | grep -m 1 "^title:" | sed 's/^title: *//; s/"//g')
        # Extract date from frontmatter
        date=$(echo "$content" | grep -m 1 "^date:" | sed 's/^date: *//; s/"//g')
    else
        title=$(grep -m 1 "^# " "$note_path" | sed 's/^# //')
        # If no date in frontmatter, use file modification time
        date=$(date -r "$note_path" +%Y-%m-%d)
    fi
    
    # If no title found, use the filename
    if [ -z "$title" ]; then
        title="$note_id"
    fi
    
    # If no date found, use current date
    if [ -z "$date" ]; then
        date=$(date +%Y-%m-%d)
    fi
    
    # Store the mapping with date for sorting by recency
    echo "$note_id:$title:$date" >> "$MAPPING_FILE"
done

echo "Starting note conversion..."

# Second pass: Process the notes with correct link titles
find "$ZK_DIR" -name "*.md" | while read note_path; do
    # Skip if this is a template file
    if [[ "$note_path" == *"$TEMPLATE_DIR"* ]]; then
        echo "Skipping template: $note_path"
        continue
    fi
    
    note_filename=$(basename "$note_path")
    note_id="${note_filename%.md}"
    
    # Create a temporary file for processing
    temp_file=$(mktemp)
    
    # Read the original file
    content=$(cat "$note_path")
    
    # Check if the file has frontmatter
    if [[ "$content" == ---* ]]; then
        # Extract title from frontmatter if it exists
        title=$(echo "$content" | grep -m 1 "^title:" | sed 's/^title: *//; s/"//g')
    else
        # Try to extract title from first heading
        title=$(grep -m 1 "^# " "$note_path" | sed 's/^# //')
        
        # If no title found, use the filename
        if [ -z "$title" ]; then
            title="$note_id"
        fi
    fi
    
    # Process the content
    processed_content="$content"
    
    # Handle links with custom text: [[note-id|Custom Text]]
    processed_content=$(echo "$processed_content" | sed -E 's/\[\[([^|]+)\|([^]]+)\]\]/[\2](\/\1)/g')
    
    # Handle links without custom text: [[note-id]]
    # For each match, look up the title in the mapping file
    while IFS= read -r link_id; do
        # Remove brackets
        clean_id=$(echo "$link_id" | sed -E 's/\[\[([^]]+)\]\]/\1/')
        
        # Look up the title in the mapping file
        target_title=$(grep "^$clean_id:" "$MAPPING_FILE" | cut -d':' -f2)
        
        # If title not found, use the ID
        if [ -z "$target_title" ]; then
            target_title="$clean_id"
        fi
        
        # Replace the link
        processed_content=$(echo "$processed_content" | sed -E "s/\[\[$clean_id\]\]/[$target_title](\/$clean_id)/g")
    done < <(echo "$processed_content" | grep -o '\[\[[^|]*\]\]')
    
    # Ensure frontmatter is properly formatted for Quartz
    if [[ "$processed_content" == ---* ]]; then
        # The file already has frontmatter, we'll use it
        echo "$processed_content" > "$temp_file"
    else
        # Create new frontmatter for the file
        echo "---
title: $title
date: $(date +%Y-%m-%d)
tags: []
---

$processed_content" > "$temp_file"
    fi
    
    # Copy processed file to Quartz content directory
    cp "$temp_file" "$QUARTZ_CONTENT_DIR/$note_filename"
    
    # Clean up
    rm "$temp_file"
    
    echo "Exported: $note_id to Quartz format"
done

# Update recent.md with the 10 most recent notes if it exists
if [ -f "$QUARTZ_CONTENT_DIR/recent.md" ]; then
    echo "Updating recent.md with top 10 recent notes..."

    # Create a temporary file for the updated recent.md
    TEMP_RECENT=$(mktemp)

    # Copy existing content up to the list of recent notes
    sed -n '/^Here are my most recently/q;p' "$QUARTZ_CONTENT_DIR/recent.md" > "$TEMP_RECENT"
    
    # Add the intro line if it doesn't exist
    if ! grep -q "^Here are my most recently" "$QUARTZ_CONTENT_DIR/recent.md"; then
        echo -e "\nHere are my most recently updated notes:\n" >> "$TEMP_RECENT"
    else
        echo -e "Here are my most recently updated notes:\n" >> "$TEMP_RECENT"
    fi

    # Sort the mapping file by date (third field) and get top 10
    sort -t':' -k3,3r "$MAPPING_FILE" | head -n 10 | while IFS=: read -r id title date; do
        echo "- [$title](/$id) - $date" >> "$TEMP_RECENT"
    done

    # Replace the old recent.md with the new one
    mv "$TEMP_RECENT" "$QUARTZ_CONTENT_DIR/recent.md"

    echo "Updated recent.md with top 10 recent notes"
else
    echo "recent.md not found, skipping recent notes update."
fi

# Clean up the mapping file
rm "$MAPPING_FILE"

echo "Export complete. Run 'npx quartz build --serve' to run the site."
