screen -ls | grep 'Dead' | grep -o '\.s[0-9]\+' | grep -o '[0-9]\+' | sort -un | xargs -I{} echo "ls -d1 [0-9]*/{}" | tr '\n' '\0' | xargs -0 -I{} bash -c "{} 2>/dev/null"
