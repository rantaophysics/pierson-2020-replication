#!/usr/bin/env bash
# Downloads the 14 statewide files used in the replication from the
# Stanford Open Policing Project (about 2.2 GB in total) into data/raw/.
# Run from the project root:  bash data/download_data.sh
set -euo pipefail
mkdir -p data/raw
cd data/raw

BASE="https://stacks.stanford.edu/file/druid:"
FILES=(
  "yg821jf8611/yg821jf8611_co_statewide_2020_04_01.rds"
  "yg821jf8611/yg821jf8611_wa_statewide_2020_04_01.rds"
  "yg821jf8611/yg821jf8611_az_statewide_2020_04_01.rds"
  "wb225bk3255/wb225bk3255_ca_statewide_2023_01_26.rds"
  "yg821jf8611/yg821jf8611_fl_statewide_2020_04_01.rds"
  "yg821jf8611/yg821jf8611_ma_statewide_2020_04_01.rds"
  "wb225bk3255/wb225bk3255_mt_statewide_2023_01_26.rds"
  "yg821jf8611/yg821jf8611_nc_statewide_2020_04_01.rds"
  "yg821jf8611/yg821jf8611_oh_statewide_2020_04_01.rds"
  "yg821jf8611/yg821jf8611_ri_statewide_2020_04_01.rds"
  "yg821jf8611/yg821jf8611_sc_statewide_2020_04_01.rds"
  "yg821jf8611/yg821jf8611_tx_statewide_2020_04_01.rds"
  "yg821jf8611/yg821jf8611_vt_statewide_2020_04_01.rds"
  "yg821jf8611/yg821jf8611_wi_statewide_2020_04_01.rds"
)

for f in "${FILES[@]}"; do
  name="${f#*/}"
  if [ -f "$name" ]; then
    echo "have $name"
  else
    echo "downloading $name"
    curl -fL --retry 3 -o "$name.part" "${BASE}${f}" && mv "$name.part" "$name"
  fi
done
echo "done: $(ls *.rds | wc -l) files in data/raw"
