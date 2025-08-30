#!/bin/bash

# sxiv key-handler here: /home/trashh_panda/.config/sxiv/exec/key-handler

# Directory with videos
VIDEO_DIR="$HOME/Videos/obs"
THUMB_DIR="/tmp/video_thumbs"
mkdir -p "$THUMB_DIR"

# Create debug file for key handler
touch /tmp/sxiv_debug.log
echo "Script started at $(date)" > /tmp/sxiv_debug.log

# Count total video files
total_videos=$(find "$VIDEO_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" \) | wc -l)
echo "Found $total_videos video files to process"

# Generate thumbnails with progress indicator
current=0
find "$VIDEO_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" \) | sort -r | while read -r video; do
    if [ -f "$video" ]; then
        current=$((current + 1))
        basename=$(basename "$video")
        thumbnail="$THUMB_DIR/${basename%.*}.jpg"
        file_size=$(du -h "$video" | cut -f1)
        
        # Show which file is being processed
        echo "Processing: $basename ($file_size)"
        
        if [ ! -f "$thumbnail" ]; then
            # Extract thumbnail at 10% of video duration with limited threads
            echo "  Generating thumbnail... (press Ctrl+C to interrupt)"
            ffmpeg -y -threads 2 -i "$video" -ss 2 -vframes 1 -vf "scale=320:-1" "$thumbnail" 2>/dev/null
            
            if [ -f "$thumbnail" ]; then
                echo "  ✓ Thumbnail created"
            else
                echo "  ✗ Failed to create thumbnail"
            fi
        else
            echo "  ✓ Thumbnail already exists"
        fi
        
        # Every 10 thumbnails, offer to view current batch
        if [ $((current % 10)) -eq 0 ] || [ "$current" -eq "$total_videos" ]; then
            echo -e "\nGenerated $current/$total_videos thumbnails."
            echo "Would you like to view current thumbnails? (y/n/q)"
            read -r view_now
            
            if [ "$view_now" = "y" ]; then
                # Create or update key-handler file with our enhanced version
                mkdir -p ~/.config/sxiv/exec/
                cat > ~/.config/sxiv/exec/key-handler << 'EOF'
#!/bin/sh

# Path for the temporary file that will store files to delete
tmp_delete_list="/tmp/sxiv_delete_list"

# Get the video file path from thumbnail - improved matching
get_video_from_thumb() {
    thumbname=$(basename "$1")
    basename="${thumbname%.*}"
    
    # Debug info to help troubleshoot
    echo "Looking for video matching thumbnail: $basename" >> /tmp/sxiv_debug.log
    
    # Try different matching patterns to be more flexible
    videofile=""
    
    # First try exact match
    videofile=$(find "$HOME/Videos/obs" -type f \( -name "${basename}.*mkv" -o -name "${basename}.*mp4" \) | head -n 1)
    
    # If that fails, try a more flexible match (in case timestamps have different separators)
    if [ -z "$videofile" ]; then
        # Extract the date part (assuming format like 2025-04-11_08-33-27)
        date_part=$(echo "$basename" | grep -o -E "[0-9]{4}-[0-9]{2}-[0-9]{2}")
        if [ -n "$date_part" ]; then
            echo "Trying flexible match with date: $date_part" >> /tmp/sxiv_debug.log
            # Look for any video with that date
            videofile=$(find "$HOME/Videos/obs" -type f \( -name "*${date_part}*.*mkv" -o -name "*${date_part}*.*mp4" \) | head -n 1)
        fi
    fi
    
    # Log the result
    if [ -n "$videofile" ]; then
        echo "Found matching video: $videofile" >> /tmp/sxiv_debug.log
    else
        echo "No matching video found for $basename" >> /tmp/sxiv_debug.log
    fi
    
    echo "$videofile"
}

while read -r file
do
        case "$1" in
        # Existing handlers
        "w") setbg "$file" & ;;
        "c")
                [ -z "$destdir" ] && destdir="$(sed "s/#.*$//;/^\s*$/d" ${XDG_CONFIG_HOME:-$HOME/.config}/shell/bm-dirs | awk '{print $2}' | dmenu -l 20 -i -p "Copy file(s) to where?" | sed "s|~|$HOME|g")"
                [ ! -d "$destdir" ] && notify-send "$destdir is not a directory, cancelled." && exit
                cp "$file" "$destdir" && notify-send -i "$(readlink -f "$file")" "$file copied to $destdir." &
                ;;
        "m")
                [ -z "$destdir" ] && destdir="$(sed "s/#.*$//;/^\s*$/d" ${XDG_CONFIG_HOME:-$HOME/.config}/shell/bm-dirs | awk '{print $2}' | dmenu -l 20 -i -p "Move file(s) to where?" | sed "s|~|$HOME|g")"
                [ ! -d "$destdir" ] && notify-send "$destdir is not a directory, cancelled." && exit
                mv "$file" "$destdir" && notify-send -i "$(readlink -f "$file")" "$file moved to $destdir." &
                ;;
        "r")
                # For video thumbnails, rename the video
                if [[ "$file" == *"/tmp/video_thumbs/"* ]]; then
                    videofile=$(get_video_from_thumb "$file")
                    if [ -n "$videofile" ]; then
                        extension="${videofile##*.}"
                        # Use dmenu for renaming if available, otherwise fallback to terminal
                        if command -v dmenu >/dev/null 2>&1; then
                            newname=$(echo "" | dmenu -p "Rename to:")
                        else
                            echo -n "Enter new name (without extension): "
                            read -r newname
                        fi
                        
                        if [ -n "$newname" ] && [ "$newname" != "$(basename "${videofile%.*}")" ]; then
                            mv "$videofile" "$(dirname "$videofile")/$newname.$extension"
                            # Also rename the thumbnail to match
                            mv "$file" "$(dirname "$file")/$newname.jpg"
                            notify-send "Renamed" "Video renamed to $newname.$extension"
                        fi
                    fi
                else
                    # Original image rotation functionality
                    convert -rotate 90 "$file" "$file"
                fi
                ;;
        "R")
                convert -rotate -90 "$file" "$file" ;;
        "f")
                convert -flop "$file" "$file" ;;
        "y")
                printf "%s" "$file" | tr -d '\n' | xclip -selection clipboard &&
                notify-send "$file copied to clipboard" & ;;
        "Y")
                readlink -f "$file" | tr -d '\n' | xclip -selection clipboard &&
                        notify-send "$(readlink -f "$file")) copied to clipboard" & ;;
        "d")
                # For video thumbnails, delete the video too
                if [[ "$file" == *"/tmp/video_thumbs/"* ]]; then
                    videofile=$(get_video_from_thumb "$file")
                    if [ -n "$videofile" ]; then
                        # Use dmenu for confirmation if available
                        if command -v dmenu >/dev/null 2>&1; then
                            confirm=$(echo -e "No\nYes" | dmenu -p "Delete $videofile?")
                            if [ "$confirm" = "Yes" ]; then
                                rm "$videofile" && notify-send "Video file deleted."
                                rm "$file" && notify-send "Thumbnail deleted."
                            fi
                        else
                            echo -n "Delete $videofile? (y/n): "
                            read -r confirm
                            if [ "$confirm" = "y" ]; then
                                rm "$videofile" && notify-send "Video file deleted."
                                rm "$file" && notify-send "Thumbnail deleted."
                            fi
                        fi
                    else
                        rm "$file" && notify-send "$file deleted."
                    fi
                else
                    rm "$file" && notify-send "$file deleted."
                fi
                ;;
        "t")
                echo "$file" >> "$tmp_delete_list" &&
                notify-send "$file tagged for deletion." ;;
        "T")
                if [ -f "$tmp_delete_list" ]; then
                    xargs rm < "$tmp_delete_list" &&
                    notify-send "All tagged files deleted." &&
                    rm "$tmp_delete_list"
                else
                    notify-send "No files tagged for deletion."
                fi ;;
        "g")    ifinstalled gimp && setsid -f gimp "$file" ;;
        "i")
                # For video thumbnails, show video info
                if [[ "$file" == *"/tmp/video_thumbs/"* ]]; then
                    videofile=$(get_video_from_thumb "$file")
                    if [ -n "$videofile" ]; then
                        filesize=$(du -h "$videofile" | cut -f1)
                        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$videofile" 2>/dev/null)
                        if [ -n "$duration" ]; then
                            duration=$(printf "%.2f minutes" "$(echo "$duration/60" | bc -l)")
                        else
                            duration="Unknown"
                        fi
                        resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$videofile" 2>/dev/null)
                        [ -z "$resolution" ] && resolution="Unknown"
                        
                        info="File: $(basename "$videofile")\nSize: $filesize\nDuration: $duration\nResolution: $resolution"
                        
                        # Use notify-send or dmenu depending on what's available
                        if command -v notify-send >/dev/null 2>&1; then
                            notify-send "Video Information" "$info"
                        else
                            echo -e "$info"
                        fi
                    else
                        notify-send "File information" "$(mediainfo "$file")"
                    fi
                else
                    notify-send "File information" "$(mediainfo "$file")"
                fi
                ;;
                
        # New video-specific handlers
        "p")
                # Play the video
                if [[ "$file" == *"/tmp/video_thumbs/"* ]]; then
                    videofile=$(get_video_from_thumb "$file")
                    if [ -n "$videofile" ]; then
                        notify-send "Playing" "$(basename "$videofile")"
                        mpv --geometry=50%x50% "$videofile" &
                    else
                        notify-send "Error" "Video file not found for $(basename "$file")"
                        # Debug which file we're looking for
                        echo "Failed to find video for thumbnail: $file" >> /tmp/sxiv_debug.log
                    fi
                fi
                ;;
        "P")
                # Play the video with custom start position (30% through)
                if [[ "$file" == *"/tmp/video_thumbs/"* ]]; then
                    videofile=$(get_video_from_thumb "$file")
                    if [ -n "$videofile" ]; then
                        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$videofile" 2>/dev/null)
                        if [ -n "$duration" ]; then
                            start=$(echo "$duration * 0.3" | bc)
                            notify-send "Playing from 30%" "$(basename "$videofile")"
                            mpv --geometry=50%x50% --start="$start" "$videofile" &
                        else
                            notify-send "Playing" "$(basename "$videofile")"
                            mpv --geometry=50%x50% "$videofile" &
                        fi
                    else
                        notify-send "Error" "Video file not found for $(basename "$file")"
                        # Debug which file we're looking for
                        echo "Failed to find video for thumbnail: $file" >> /tmp/sxiv_debug.log
                    fi
                fi
                ;;
        esac
done
EOF
                chmod +x ~/.config/sxiv/exec/key-handler
                
                # Display keyboard shortcuts
                echo "sxiv keyboard shortcuts:"
                echo "  Arrow keys: Navigate between images"
                echo "  Enter: View full-size image"
                echo "  Space: Toggle between thumbnail/image view"
                echo "  Ctrl+x then p: Play the selected video"
                echo "  Ctrl+x then P: Play the selected video (start at 30%)"
                echo "  Ctrl+x then r: Rename the selected video"
                echo "  Ctrl+x then d: Delete the selected video"
                echo "  Ctrl+x then i: Show video information"
                echo "  q: Quit sxiv"
                echo ""
                echo "Opening thumbnail gallery..."
                
                # Use sxiv to display thumbnails in a grid
                sxiv -t "$THUMB_DIR"/*.jpg
                
                # Interactive mode after viewing thumbnails
                echo "Would you like to (p)review videos, (r)ename files, (d)elete files, or (c)ontinue generating thumbnails? (p/r/d/c/q)"
                read -r mode
                
                case "$mode" in
                    p)
                        echo "Enter thumbnail number to preview video:"
                        read -r thumbnail_number
                        thumbnail_file=$(ls "$THUMB_DIR"/*.jpg | sed -n "${thumbnail_number}p")
                        if [ -n "$thumbnail_file" ]; then
                            video_basename=$(basename "$thumbnail_file" .jpg)
                            video_file=$(find "$VIDEO_DIR" -name "${video_basename}.*" | head -n 1)
                            mpv --geometry=50%x50% "$video_file"
                        fi
                        ;;
                    r)
                        echo "Enter thumbnail number of file to rename:"
                        read -r thumbnail_number
                        thumbnail_file=$(ls "$THUMB_DIR"/*.jpg | sed -n "${thumbnail_number}p")
                        if [ -n "$thumbnail_file" ]; then
                            video_basename=$(basename "$thumbnail_file" .jpg)
                            video_file=$(find "$VIDEO_DIR" -name "${video_basename}.*" | head -n 1)
                            echo "Current name: $video_file"
                            echo "Enter new name (without extension):"
                            read -r new_name
                            extension="${video_file##*.}"
                            mv "$video_file" "$(dirname "$video_file")/$new_name.$extension"
                            echo "File renamed."
                        fi
                        ;;
                    d)
                        echo "Enter thumbnail number of file to delete:"
                        read -r thumbnail_number
                        thumbnail_file=$(ls "$THUMB_DIR"/*.jpg | sed -n "${thumbnail_number}p")
                        if [ -n "$thumbnail_file" ]; then
                            video_basename=$(basename "$thumbnail_file" .jpg)
                            video_file=$(find "$VIDEO_DIR" -name "${video_basename}.*" | head -n 1)
                            echo "Delete $video_file? (y/n)"
                            read -r confirm
                            if [ "$confirm" = "y" ]; then
                                rm "$video_file"
                                echo "File deleted."
                            fi
                        fi
                        ;;
                    q)
                        echo "Exiting."
                        rm -rf "$THUMB_DIR"
                        exit 0
                        ;;
                    c)
                        echo "Continuing thumbnail generation..."
                        ;;
                esac
            elif [ "$view_now" = "q" ]; then
                echo "Exiting."
                rm -rf "$THUMB_DIR"
                exit 0
            fi
        fi
        
        echo "-------------------------------------------"
    fi
done

echo "All thumbnails generated!"

# Final view of all thumbnails
echo "Do you want to open the thumbnail gallery? (y/n)"
read -r view_all
if [ "$view_all" = "y" ]; then
    # Display keyboard shortcuts again
    echo "sxiv keyboard shortcuts:"
    echo "  Arrow keys: Navigate between images"
    echo "  Enter: View full-size image"
    echo "  Space: Toggle between thumbnail/image view"
    echo "  Ctrl+x then p: Play the selected video"
    echo "  Ctrl+x then P: Play the selected video (start at 30%)"
    echo "  Ctrl+x then r: Rename the selected video"
    echo "  Ctrl+x then d: Delete the selected video"
    echo "  Ctrl+x then i: Show video information"
    echo "  q: Quit sxiv"
    echo ""
    echo "Opening thumbnail gallery..."
    
    # Use sxiv to display thumbnails in a grid
    sxiv -t "$THUMB_DIR"/*.jpg
    
    # Interactive bulk operations after viewing all thumbnails
    echo "Bulk operations: (r)ename multiple files, (d)elete multiple files, (e)xit"
    read -r bulk_op
    
    case "$bulk_op" in
        r)
            # Add bulk renaming interface here
            echo "Bulk renaming not implemented yet"
            ;;
        d)
            # Add bulk deletion interface here
            echo "Bulk deletion not implemented yet"
            ;;
        *)
            echo "Exiting."
            ;;
    esac
fi

# Clean up option
echo "Keep thumbnail cache for future use? (y/n)"
read -r keep_cache
if [ "$keep_cache" = "n" ]; then
    rm -rf "$THUMB_DIR"
    echo "Thumbnail cache removed."
else
    echo "Thumbnail cache kept at $THUMB_DIR for faster access next time"
fi