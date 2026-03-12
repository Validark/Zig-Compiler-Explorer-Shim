#!/bin/bash

if [ "$1" = "latest" ]; then
  git pull origin main
  # Delete the silly tooltip messages
  sed -i '' "s|const attSyntaxWarning = '\*\*\*WARNING: The information shown pertains to Intel syntax\.\*\*\*';|const attSyntaxWarning = '';|" ./static/panes/compiler.ts
  sed -i '' "s|value: response.tooltip + '\\\\n\\\\nMore information available in the context menu.',|value: response.tooltip,|" ./static/panes/compiler.ts
  make prebuild EXTRA_ARGS='--language zig'
  # Restore the silly tooltip messages
  sed -i '' "s|const attSyntaxWarning = '';|const attSyntaxWarning = '\*\*\*WARNING: The information shown pertains to Intel syntax\.\*\*\*';|" ./static/panes/compiler.ts
  sed -i '' "s|value: response.tooltip,|value: response.tooltip + '\\\\n\\\\nMore information available in the context menu.',|" ./static/panes/compiler.ts
fi

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
group.zig.options=-O ReleaseFast -fomit-frame-pointer -freference-trace=100
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
compiler.$version_alias.name=$version
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
Filled $output_file with $i Zig Compilers"

tools_list=()

llvm_mca_version=""
llvm_mca_path=""
echo -n "Searching for llvm-mca => "
if command -v llvm-mca >/dev/null 2>&1; then
  tools_list+=("llvm-mca")
  llvm_mca_version=$(llvm-mca --version | sed -n 's/.*LLVM version \([0-9.]*\).*/\1/p')
  llvm_mca_path=$(command -v llvm-mca)
  echo "found $llvm_mca_path (version $llvm_mca_version)"
else
  echo "not found"
fi

osaca_version=""
osaca_path=""
echo -n "Searching for osaca => "
if command -v osaca >/dev/null 2>&1; then
  tools_list+=("osaca")
  osaca_version=$(osaca --version)
  osaca_path=$(command -v osaca)
  echo "found $osaca_path (version $osaca_version)"
else
  echo "not found"
fi

echo ""
echo ""

{
  if [ ${#tools_list[@]} -gt 0 ]; then
    printf 'tools=%s\n' "$(IFS=:; echo "${tools_list[*]}")"
  fi

  if [ -n "$llvm_mca_path" ]; then
    echo "tools.llvm-mca.name=llvm-mca $llvm_mca_version"
    echo "tools.llvm-mca.exe=$llvm_mca_path"
    echo "tools.llvm-mca.type=postcompilation"
    echo "tools.llvm-mca.class=llvm-mca-tool"
    echo "tools.llvm-mca.options=-timeline"
    echo "tools.llvm-mca.stdinHint=disabled"
  fi

  if [ -n "$osaca_path" ]; then
    echo "tools.osaca.name=$osaca_version"
    echo "tools.osaca.exe=$osaca_path"
    echo "tools.osaca.type=postcompilation"
    echo "tools.osaca.class=osaca-tool"
    echo "tools.osaca.stdinHint=disabled"
  fi
} >> "$output_file"

# make dev EXTRA_ARGS='--language zig --debug'
make run-only EXTRA_ARGS='--language zig'
