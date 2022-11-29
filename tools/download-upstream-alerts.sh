#!/bin/bash
set -e

if [ $# -lt 2 ]; then
  echo "Usage: $0 <alerts-txt> <output-dir>"
  exit 3
fi

alerts_txt=$1
output_dir=$2

IFS=$'\n' read -d '' -r -a downloads < <(cat "$alerts_txt";printf '\0')

for i in "${downloads[@]}"; do
  read -r url l _ <<<"$i"
  l="$output_dir/$l"

  echo "Downloading $url to $l"

  mkdir -p "$(dirname "$l")"

  if [[ "$url" == *".yaml" || "$url" == *".yml" ]]; then
      echo "Downloading yaml directly from $url"
      wget --no-verbose -O "$l" "$url"
  else
    extract=${url##*.}
    url=${url%.*}

    echo "Downloading $url (needs extraction)"
    wget --no-verbose -O "$l~" "$url"
    echo "Extracting $l~ Go constant $extract to $l"
    go run github.com/bastjan/declextract@latest "$l~" "$extract" > "$l"
    rm "$l~"
  fi
done
