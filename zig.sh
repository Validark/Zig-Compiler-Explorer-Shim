#!/bin/bash

exe_location=$(readlink -f "$(whereis zig | cut -d ' ' -f 2)")
searcher=$(echo "$exe_location" | sed -E 's#[0-9]+\.[0-9]+\.[0-9]+[^/]*#*#')
prefix=$(echo "$searcher" | cut -d '*' -f 1)
suffix=$(echo "$searcher" | cut -d '*' -f 2)

echo "
Searching for Zig compilers in $searcher"

zig_version=$(zig version)
output_file="./etc/config/zig.local.properties"

echo "compilers=&zig
group.zig.objdumper=objdump
group.zig.isSemVer=true
group.zig.baseName=zig
group.zig.compilerType=zig
group.zig.versionFlag=version
group.zig.licenseLink=https://github.com/ziglang/zig/blob/master/LICENSE
group.zig.licenseName=The MIT License (Expat)
group.zig.licensePreamble=Copyright (c) Zig contributors
group.zig.needsMulti=true
group.zig.options=-O ReleaseFast
" > "$output_file"

# Empty the output file on Ctrl+C
cleanup() {
  echo "" > "$output_file"
  exit 1
}

# Trap the SIGINT signal (Ctrl+C) and call the cleanup function
trap cleanup SIGINT

versions=()
version_aliases=()
default_compiler=""
default_compiler_version=""

for folder in "$prefix"*; do
  if [ -d "$folder" ]; then
    if [[ "$folder" == "$(readlink -f "$folder")" ]]; then
      version=${folder#"$prefix"}  # Remove prefix
      version=${version%"$suffix"}      # Remove suffix

      # Generate version_alias by replacing . and + with -
      version_alias=${version//[.+]/-}

      echo "compiler.$version_alias.exe=$folder$suffix
compiler.$version_alias.semver=$version
compiler.$version_alias.name=v$version
" >> "$output_file"

      versions+=("$version")
      version_aliases+=("$version_alias")

      # Check if this version matches the detected Zig version
      if [[ "$version" == "$zig_version" && -z "$default_compiler" ]]; then
        default_compiler="$version_alias"
        default_compiler_version="$version"
      fi
    fi
  fi
done

sorted_versions=$(echo "${versions[@]}" | tr ' ' '\n' | sort -r)
sorted_version_aliases=$(echo "${version_aliases[@]}" | tr ' ' '\n' | sort -r | tr '\n' ':')
sorted_version_aliases="${sorted_version_aliases%:}" # Remove trailing colon

# Output the final line with all version aliases
echo "group.zig.compilers=$sorted_version_aliases" >> "$output_file"

if [ -n "$default_compiler" ]; then
  echo "defaultCompiler=$default_compiler" >> "$output_file"
else
  default_compiler=$(echo "$sorted_version_aliases" | cut -d':' -f 1)
  default_compiler_version=$(echo "$sorted_versions" | head -n 1)
  echo "defaultCompiler=$default_compiler" >> "$output_file"
fi

echo "
Found Zig versions:"

i=0;

while IFS= read -r sorted_version; do
    ((i++))
    is_default=""
    if [[ "$sorted_version" == "$default_compiler_version" ]]; then
      is_default=" (DEFAULT)"
    fi
    echo "    $sorted_version$is_default"
done <<< "$sorted_versions"

echo "
Filled $output_file with $i Zig Compilers
"

# make dev EXTRA_ARGS='--language zig --debug'
make run-only EXTRA_ARGS='--language zig'
