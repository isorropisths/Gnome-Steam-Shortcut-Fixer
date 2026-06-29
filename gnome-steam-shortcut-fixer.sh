#!/bin/bash

# Functions
# Function to init the variables
initVariables() {
    # Variables
    shortcutsPath="$HOME/.local/share/applications"
    iconsPath="$HOME/.local/share/icons/hicolor/"
    steamLibraryConfigVdf="$HOME/.local/share/Steam/config/libraryfolders.vdf"
    steamInstallType="native"

    if [ ! -f "$steamLibraryConfigVdf" ]; then
        # If the default path returns nothing try the flatpak path
        echo -e "\e[31mSteam library config file not found in the default path. Trying the flatpak path\e[0m"
        steamLibraryConfigVdf="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/config/libraryfolders.vdf"
        steamInstallType="flatpak"
        if [ ! -f "$steamLibraryConfigVdf" ]; then
            # If both the default path, and flatpak path are nil, try snap path
            echo -e "\e[31mSteam library config file not found in flatpak path. Trying the snap path\e[0m"
            steamLibraryConfigVdf="$HOME/snap/steam/common/.local/share/Steam/config/libraryfolders.vdf"
            steamInstallType="snap"
            if [ ! -f "$steamLibraryConfigVdf" ]; then
              echo -e "\e[31mError: Steam library config file not found\e[0m"
              exit 1
            fi

        fi
    fi
    echo -e "\e[32mSteam library config file found at $steamLibraryConfigVdf\e[0m"
}


# Function to fix the existing shortcuts
fixExistingShortcuts() {
    echo -e "\e[90mFixing existing shortcuts\e[0m"
    # Get all the .desktop files in the .local/share/applications folder
    while IFS= read -r -d '' desktopFile; do
        shortcutFiles+=("$desktopFile")
    done < <(find "$shortcutsPath" -name "*.desktop" -print0)
    echo -e "\e[90mFound ${#shortcutFiles[@]} existing shortcuts\e[0m"
    echo -e "\e[90m--------------------------\e[0m"
    # Loop through all the .desktop files and check for a steam launch pattern
    # Then get the ID from the exec and add/update the StartupWMClass
    for shortcutFile in "${shortcutFiles[@]}"
    do
        # Get the exec line from the .desktop file
        gameName=$(grep -oP '^Name=.*' "$shortcutFile" | cut -d'=' -f2-)
        if [ "$gameName" == "Steam" ]; then
            echo -e "\e[90mSkipping Steam shortcut\e[0m"
            echo -e "\e[90m--------------------------\e[0m"
            continue
        fi
        execLine=$(grep -oP '^Exec=.*' "$shortcutFile" | cut -d'=' -f2-)
        
        # Extract appId using regex matching to handle different formats (native, flatpak, snap, non-Steam)
        appId=""
        if [[ "$execLine" =~ steam://rungameid/([0-9]+) ]]; then
            appId="${BASH_REMATCH[1]}"
        elif [[ "$execLine" =~ rungameid/([0-9]+) ]]; then
            appId="${BASH_REMATCH[1]}"
        elif [[ "$execLine" =~ -applaunch[[:space:]]+([0-9]+) ]]; then
            appId="${BASH_REMATCH[1]}"
        fi

        if [ -n "$appId" ]; then
            # Convert 64-bit GameID (non-Steam game) to 32-bit AppID
            originalAppId="$appId"
            if python3 -c "exit(0)" 2>/dev/null; then
                shiftedAppId=$(python3 -c "print(($appId >> 32) & 0xffffffff)")
            else
                shiftedAppId=$(echo "$appId / 4294967296" | bc 2>/dev/null)
            fi
            if [ -n "$shiftedAppId" ] && [ "$shiftedAppId" -ne 0 ]; then
                appId=$shiftedAppId
                echo -e "\e[32mFixing $gameName, converting non-Steam game ID $originalAppId to AppID: $appId\e[0m"
            else
                echo -e "\e[32mFixing $gameName, with app id: $appId\e[0m"
            fi

            # Check if the StartupWMClass already exists and is correct
            if grep -q "^StartupWMClass=" "$shortcutFile"; then
                if grep -qFx "StartupWMClass=steam_app_$appId" "$shortcutFile"; then
                    echo -e "\e[90mStartupWMClass is already correct, skipped\e[0m"
                    echo -e "\e[90m--------------------------\e[0m"
                else
                    # Update StartupWMClass
                    sed -i "s|^StartupWMClass=.*|StartupWMClass=steam_app_$appId|" "$shortcutFile"
                    echo -e "\e[32mStartupWMClass updated in $shortcutFile\e[0m"
                    echo -e "\e[90m--------------------------\e[0m"
                fi
            else
                # Add the StartupWMClass to the .desktop file
                echo "StartupWMClass=steam_app_$appId" >> "$shortcutFile"
                echo -e "\e[32mStartupWMClass added to $shortcutFile\e[0m"
                echo -e "\e[90m--------------------------\e[0m"
            fi
        fi
    done
}

# Get all the installed appIds from the libraryfolders.vdf file
getAllLibraryFolders() {
    # Get the IDS
    libraryFolders=($(    grep -oP '(?<="path"\t\t").*(?=")' "$steamLibraryConfigVdf"))
    echo -e "\e[90mFound ${#libraryFolders[@]} library folders\e[0m"
}

# In the library folders get the installed apps ids from the appmanifest files
getInstalledAppIds() {
    # Loop through all the library folders
    for libraryFolder in "${libraryFolders[@]}"
    do
        # Check if the steamapps folder exists in the library folder
        if [ -d "$libraryFolder/steamapps" ]; then
            # Get the appmanifest files in the steamapps folder
            appManifestFiles=($(find "$libraryFolder/steamapps" -name "appmanifest_*.acf"))
            echo -e "\e[90mFound ${#appManifestFiles[@]} appmanifest files in $libraryFolder\e[0m"
            # Loop through all the appmanifest files
            for appManifestFile in "${appManifestFiles[@]}"
            do
                # Get the appid from the appmanifest file
                appId=$(grep -oP '(?<="appid"\t\t").*(?=")' "$appManifestFile")
                appIds+=("$appId")
            done
        else
            echo -e "\e[31mError: steamapps folder not found in $libraryFolder\e[0m"
        fi
    done
}
# Function to create shortcuts for Non-Steam games
createNonSteamShortcuts() {
    if ! command -v python3 &>/dev/null; then
        echo -e "\e[31mWarning: python3 is not installed. Skipping Non-Steam game shortcut creation.\e[0m"
        return
    fi

    echo -e "\e[90m--------------------------\e[0m"
    echo -e "\e[90mCreating shortcuts for Non-Steam games\e[0m"

    steamBaseDir="$(dirname "$(dirname "$steamLibraryConfigVdf")")"
    userdataDir="$steamBaseDir/userdata"

    if [ ! -d "$userdataDir" ]; then
        userdataDir="$HOME/.steam/steam/userdata"
    fi

    if [ -d "$userdataDir" ]; then
        # Find all shortcuts.vdf files
        while IFS= read -r -d '' shortcutsVdf; do
            echo -e "\e[90mFound shortcuts file: $shortcutsVdf\e[0m"
            python3 - "$shortcutsVdf" "$steamInstallType" "$shortcutsPath" << 'EOF'
import os
import sys
import glob

def parse_binary_vdf(data):
    i = 0
    length = len(data)
    
    def read_string():
        nonlocal i
        start = i
        while i < length and data[i] != 0:
            i += 1
        s = data[start:i].decode('utf-8', errors='ignore')
        i += 1
        return s

    def read_wstring():
        nonlocal i
        start = i
        while i < length - 1 and not (data[i] == 0 and data[i+1] == 0):
            i += 2
        s = data[start:i].decode('utf-16le', errors='ignore')
        i += 2
        return s

    def read_int32():
        nonlocal i
        val = int.from_bytes(data[i:i+4], byteorder='little')
        i += 4
        return val

    def read_int64():
        nonlocal i
        val = int.from_bytes(data[i:i+8], byteorder='little')
        i += 8
        return val

    def read_map():
        nonlocal i
        res = {}
        while i < length:
            t = data[i]
            i += 1
            if t == 8:
                break
            key = read_string()
            if t == 0:
                res[key] = read_map()
            elif t == 1:
                res[key] = read_string()
            elif t == 2:
                res[key] = read_int32()
            elif t == 3 or t == 4 or t == 6:
                i += 4
            elif t == 5:
                res[key] = read_wstring()
            elif t == 7 or t == 9:
                res[key] = read_int64()
            else:
                pass
        return res

    if i < length and data[i] == 0:
        i += 1
        root_key = read_string()
        return {root_key: read_map()}
    return {}

def main():
    if len(sys.argv) < 4:
        return
    shortcuts_vdf = sys.argv[1]
    steam_install_type = sys.argv[2]
    shortcuts_path = sys.argv[3]
    
    userdata_dir = os.path.dirname(os.path.dirname(os.path.dirname(shortcuts_vdf)))
    user_id = os.path.basename(os.path.dirname(os.path.dirname(shortcuts_vdf)))
    grid_dir = os.path.join(userdata_dir, user_id, "config", "grid")

    try:
        with open(shortcuts_vdf, 'rb') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading shortcuts.vdf: {e}", file=sys.stderr)
        return

    parsed = parse_binary_vdf(content)
    shortcuts = parsed.get('shortcuts', {})
    if not shortcuts:
        return

    for key, entry in shortcuts.items():
        app_name = entry.get('AppName') or entry.get('appname')
        appid = entry.get('appid')
        if not app_name or not appid:
            continue
        
        # Calculate 64-bit GameID
        game_id = (appid << 32) | 0x02000000
        
        # Check for custom icon in grid directory
        icon_path = "steam"
        if os.path.exists(grid_dir):
            patterns = [
                os.path.join(grid_dir, f"{appid}_icon.png"),
                os.path.join(grid_dir, f"{appid}_icon.jpg"),
                os.path.join(grid_dir, f"{appid}_icon.jpeg"),
                os.path.join(grid_dir, f"{appid}_icon.tga"),
            ]
            for p in patterns:
                if os.path.exists(p):
                    icon_path = p
                    break
            else:
                matches = glob.glob(os.path.join(grid_dir, f"{appid}_icon.*"))
                if matches:
                    icon_path = matches[0]

        if steam_install_type == "flatpak":
            exec_cmd = f"flatpak run com.valvesoftware.Steam steam steam://rungameid/{game_id}"
        elif steam_install_type == "snap":
            exec_cmd = f"snap run steam steam://rungameid/{game_id}"
        else:
            exec_cmd = f"steam steam://rungameid/{game_id}"

        desktop_file_path = os.path.join(shortcuts_path, f"{app_name}.desktop")
        
        try:
            with open(desktop_file_path, 'w') as df:
                df.write("[Desktop Entry]\n")
                df.write(f"Name={app_name}\n")
                df.write(f"Comment=Play {app_name} on Steam\n")
                df.write(f"Exec={exec_cmd}\n")
                df.write(f"Icon={icon_path}\n")
                df.write("Terminal=false\n")
                df.write("Type=Application\n")
                df.write("Categories=Game;\n")
                df.write(f"StartupWMClass=steam_app_{appid}\n")
                df.write("NoDisplay=true\n")
            print(f"\033[32mCreated shortcut for Non-Steam game: {app_name}\033[0m")
        except Exception as e:
            print(f"Error writing desktop file for {app_name}: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()
EOF
        done < <(find "$userdataDir" -maxdepth 3 -name "shortcuts.vdf" -print0 2>/dev/null)
    else
        echo -e "\e[31mError: Steam userdata directory not found at $userdataDir\e[0m"
    fi
}

# Function to create/replace new shortcuts for all games
createNewShortcuts() {
    # Get the library folders from the libraryfolders.vdf file
    getAllLibraryFolders
    # Get all the installed appIds from the appmanifest files in the steamapps folder for all the library folders
    getInstalledAppIds
    # Loop through all the previously found appIds and create a shortcut for each game
    echo -e "\e[90m--------------------------\e[0m"
    for appId in "${appIds[@]}"
    do 
        # Create a shortcut for each game in the steamapps/compatdata folder
        # First, retrieve the name of the game from Steam API
        gameName=$(curl -s "https://store.steampowered.com/api/appdetails?appids=$appId" | jq -r ".\"$appId\".data.name")
        # If the game name is not null, then create a shortcut for the game in .local/share/applications
        if [ "$gameName" != "null" ]; then
            # Check if the icon exists in the .local/share/icons/hicolor/48x48/apps folder
            gameIcon=$(find "$iconsPath" | grep "steam_icon_$appId.png")

            echo -e "\e[32mCreating shortcut for $gameName\e[0m"
            echo -e "\e[90m--------------------------\e[0m"
            echo "[Desktop Entry]" > "$shortcutsPath/$gameName.desktop"
            echo "Name=$gameName" >> "$shortcutsPath/$gameName.desktop"

            case "$steamInstallType" in
                flatpak)
                    echo "Exec=flatpak run com.valvesoftware.Steam steam steam://rungameid/$appId" >> "$shortcutsPath/$gameName.desktop"
                    ;;
                snap)
                    echo "Exec=snap run steam -applaunch $appId" >> "$shortcutsPath/$gameName.desktop"
                    ;;
                *)
                    echo "Exec=steam steam://rungameid/$appId" >> "$shortcutsPath/$gameName.desktop"
                    ;;
            esac
            # -----------------------------

            echo "Type=Application" >> "$shortcutsPath/$gameName.desktop"

            if [ -n "$gameIcon" ]; then
                echo "Icon=steam_icon_$appId" >> "$shortcutsPath/$gameName.desktop"
            else
                echo "Icon=steam" >> "$shortcutsPath/$gameName.desktop"
            fi

            echo "Type=Application" >> "$shortcutsPath/$gameName.desktop"
            # If the icon exists, then use it, otherwise use the default steam icon
            if [ -n "$gameIcon" ]; then
                echo "Icon=steam_icon_$appId" >> "$shortcutsPath/$gameName.desktop"
            else
                echo "Icon=steam" >> "$shortcutsPath/$gameName.desktop"
            fi
            echo "Categories=Game;" >> "$shortcutsPath/$gameName.desktop"
            echo "Terminal=false" >> "$shortcutsPath/$gameName.desktop"
            echo "StartupWMClass=steam_app_$appId" >> "$shortcutsPath/$gameName.desktop"
            echo "Comment=Play $gameName on Steam" >> "$shortcutsPath/$gameName.desktop"
            echo "NoDisplay=true" >> "$shortcutsPath/$gameName.desktop"
        else
            echo -e "\e[31mError: Name not found for $appId (it is probably not a game and doesn't need a shortcut)\e[0m"
            echo -e "\e[90m--------------------------\e[0m"
        fi
    done

    # Create shortcuts for Non-Steam games
    createNonSteamShortcuts
}

# Function to display the help message
helpCommand() {
    echo "Usage: gnome-steam-shortcut-fixer.sh [OPTION]"
    echo "Fix or create new shortcuts for Steam games running with Proton on GNOME"
    echo "Note: this utility will create and fix shortcuts even for native games not running with Proton, but the default icon won't be fixed for these games"
    echo "Options:"
    echo "  -h, --help      Display this help message"
    echo "  -f, --fix       Fix existing shortcuts"
    echo "  -c, --create    Create new shortcuts for all games (Steam and Non-Steam)"
    echo "  -n, --nonsteam  Create new shortcuts for Non-Steam games only"
}

# Main
# Route the command line arguments
case "$1" in
    -h|--help)
        helpCommand
        exit 0
        ;;
    -f|--fix)
        initVariables
        fixExistingShortcuts
        exit 0
        ;;
    -c|--create)
        initVariables
        createNewShortcuts
        exit 0
        ;;
    -n|--nonsteam)
        initVariables
        createNonSteamShortcuts
        exit 0
        ;;
    *)
        echo "Invalid option. Use -h or --help for help"
        exit 1
        ;;
esac
