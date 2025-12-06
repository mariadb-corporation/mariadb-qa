#!/bin/bash
set -e

# Copy this script to your source dir and change this example list of target commits to be removed. Then execute.
TARGETS=(
  "aeb0dbd1270310a7ac1f7eae7ce9b606487de8f6"
  "f7cb528bdf28907cae25e9033104d1c2a10d4685"
  "f1ab655cc0610b6364a165dff7c96e45290c2bbf"
)

echo "=========================================="
echo "STEP 1: PRE-FLIGHT CHECK"
echo "Checking which patches exist in current history..."
echo "=========================================="

VALID_HASHES=()
for hash in "${TARGETS[@]}"; do
    # Check if hash is reachable from HEAD
    if git merge-base --is-ancestor "$hash" HEAD 2>/dev/null; then
        echo " [YES] Found $hash in history."
        VALID_HASHES+=("$hash")
    else
        echo " [NO]  Skipping $hash (not found in current branch history)."
    fi
done

COUNT=${#VALID_HASHES[@]}
if [ "$COUNT" -eq 0 ]; then
    echo "No patches found to remove. Exiting."
    exit 0
fi

# Create a space-separated string of targets for the editor script to use
TARGET_STRING=" ${VALID_HASHES[*]} "

echo "------------------------------------------"
echo "Found $COUNT patches to remove."

# Calculate the oldest commit to determine where to start rebasing
OLDEST_COMMIT=$(git rev-list --topo-order --no-walk "${VALID_HASHES[@]}" | tail -1)
REBASE_BASE="${OLDEST_COMMIT}^"
echo "Oldest patch is $OLDEST_COMMIT"
echo "Rebase base set to parent: $REBASE_BASE"


echo "=========================================="
echo "STEP 2: GENERATING DEBUG EDITOR"
echo "=========================================="

EDITOR_SCRIPT="./.git_verbose_editor.sh"

# Write a bash script that will act as the 'editor' for git rebase.
# It prints to /dev/tty to enable seeing the output even if git buffers it.
cat <<EOF > "$EDITOR_SCRIPT"
#!/bin/bash
TODO_FILE="\$1"
TEMP_FILE="\${TODO_FILE}.tmp"
TARGETS="$TARGET_STRING"

# Redirect echo to /dev/tty to ensure the user sees it on screen
exec 3>/dev/tty

echo "--- REBASE EDITOR ACTIVE ---" >&3

while IFS= read -r line; do
    # Match lines starting with 'pick' followed by a hash
    if [[ "\$line" =~ ^pick\ ([0-9a-f]+) ]]; then
        SHORT_HASH="\${BASH_REMATCH[1]}"
        
        # Resolve short hash to full hash for accurate comparison
        FULL_HASH=\$(git rev-parse "\$SHORT_HASH")
        
        # Check if this hash is in the target list
        if [[ "\$TARGETS" == *" \$FULL_HASH "* ]]; then
            echo " [ACTION] DROPPING: \$SHORT_HASH (\$FULL_HASH)" >&3
            # Write 'drop' instead of 'pick'
            echo "drop \${line#pick }" >> "\$TEMP_FILE"
            continue
        else
             # Optional: Uncomment to see what is being kept
             # echo " [ACTION] Keeping : \$SHORT_HASH" >&3
             :
        fi
    fi
    
    # If not dropped, write the original line
    echo "\$line" >> "\$TEMP_FILE"
done < "\$TODO_FILE"

# Replace original todo file with the modified version
mv "\$TEMP_FILE" "\$TODO_FILE"
EOF

chmod +x "$EDITOR_SCRIPT"
echo "Editor script created at $EDITOR_SCRIPT"

echo "=========================================="
echo "STEP 3: RUNNING REBASE"
echo "=========================================="

export GIT_SEQUENCE_EDITOR="$EDITOR_SCRIPT"

# Run the rebase
if git rebase -i "$REBASE_BASE"; then
    echo "Git Rebase reported success."
else
    echo "Git Rebase failed. You may need to run 'git rebase --abort'."
    rm "$EDITOR_SCRIPT"
    exit 1
fi

# Cleanup
rm "$EDITOR_SCRIPT"
unset GIT_SEQUENCE_EDITOR

echo "=========================================="
echo "STEP 4: FINAL VERIFICATION"
echo "=========================================="

REMAINING=0
for hash in "${VALID_HASHES[@]}"; do
    if git merge-base --is-ancestor "$hash" HEAD 2>/dev/null; then
        echo " [FAIL] Patch $hash STILL exists in history."
        ((REMAINING++))
    else
        echo " [OK]   Patch $hash is gone."
    fi
done

echo "------------------------------------------"
if [ "$REMAINING" -eq 0 ]; then
    echo "SUCCESS! All patches removed."
    echo ""
    echo "NOTE on 'git diff' vs 'git log':"
    echo "Do not use 'git diff' as it will be empty because 'diff' shows *uncommitted* changes only."
    echo "We successfully rewrote the *committed* history: use 'git log' to confirm the history is correct."
    echo "For example: git log --oneline | grep 'a_commit_id'"
else
    echo "FAILURE: $REMAINING patches remain."
fi
