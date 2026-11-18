#!/bin/bash
set -euo pipefail
shopt -s nullglob

project_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
applications_dir="$HOME/Applications"
destination="$applications_dir/悬浮待办.app"
sources=("$project_dir"/Sources/FloatingTodo/*.swift)

if (( ${#sources[@]} == 0 )); then
    echo "No Swift sources found in $project_dir/Sources/FloatingTodo." >&2
    exit 1
fi

info_plist="$project_dir/Info.plist"
minimum_system="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
# File Provider can attach Finder metadata to app bundles under Documents.
temporary_dir="${TMPDIR:-/tmp}"
staging="$(mktemp -d "${temporary_dir%/}/floating-todo-build.XXXXXX")"
bundle="$staging/悬浮待办.app"
previous_bundle="$staging/previous.app"

cleanup() {
    if [[ -d "$previous_bundle" && ! -e "$destination" ]]; then
        if ! mv -- "$previous_bundle" "$destination"; then
            echo "Previous app preserved at $previous_bundle." >&2
            return
        fi
    fi
    find "$staging" -depth -delete
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp -X "$info_plist" "$bundle/Contents/Info.plist"
cp -X "$project_dir/Resources/AppIcon.icns" "$bundle/Contents/Resources/"

xcrun --sdk macosx swiftc -O -parse-as-library \
    -target "$(uname -m)-apple-macosx$minimum_system" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -module-name FloatingTodo \
    "${sources[@]}" -o "$bundle/Contents/MacOS/FloatingTodo"

codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"

mkdir -p "$applications_dir"
if [[ -e "$destination" || -L "$destination" ]]; then
    if [[ -L "$destination" ]] || ! /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "$destination/Contents/Info.plist" 2>/dev/null | /usr/bin/grep -Fxq "$bundle_id"; then
        echo "Refusing to replace a different app at $destination." >&2
        exit 1
    fi
    mv -- "$destination" "$previous_bundle"
fi

mv -- "$bundle" "$destination"
if ! codesign --verify --strict "$destination"; then
    mv -- "$destination" "$bundle"
    exit 1
fi
printf '%s\n' "$destination"
