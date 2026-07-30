"""
STEP 1 — Filter BACI to Rare Earth HS Codes
════════════════════════════════════════════
Run this first. It reads all 13 BACI year-files, keeps only the
7 rare-earth HS codes, merges ISO3 country names, assigns supply-chain
layers, and saves one clean CSV you will use in all later steps.

HOW TO RUN (Terminal / Anaconda Prompt):
    cd /path/to/this/file
    python Step1_Filter_BACI.py

Time: ~3-5 minutes for all 13 years.
Output: rare_earth_network_paper/data/01_baci_ree_filtered.csv
"""

import pandas as pd
import os, time

# ── CONFIGURE THESE PATHS ──────────────────────────────────────
BACI_DIR    = "/Users/sanayounas/Downloads/BACI_HS12_V202601"   # folder with BACI CSVs
OUTPUT_DIR  = "/Users/sanayounas/Claude/Projects/Netwrok/data"   # where to save results
# ──────────────────────────────────────────────────────────────

os.makedirs(OUTPUT_DIR, exist_ok=True)

# ── HS CODES: 7 codes across 3 supply-chain layers ────────────
HS_LAYER = {
    "261790": 1,   # Upstream  — REE ores & concentrates (OTHER ores NEC ch.26)
    "253090": 1,   # Upstream  — Other mineral substances (broad, robustness only)
    "284690": 2,   # Midstream — REE compounds, oxides, chlorides  ← MAIN Layer 2
    "284610": 2,   # Midstream — Cerium compounds (broad)
    "280530": 2,   # Midstream — REE metals, scandium, yttrium (refined)
    "850511": 3,   # Downstream— Permanent magnets of metal  ← MAIN Layer 3
    "850519": 3,   # Downstream— Other permanent magnets (broad)
}

# ── Country codes (provided by CEPII with BACI) ───────────────
cc_path = os.path.join(BACI_DIR, "country_codes_V202601.csv")
country_codes = pd.read_csv(cc_path)
# build lookup: numeric_code → iso3
code_to_iso3 = dict(zip(country_codes["country_code"], country_codes["country_iso3"]))
code_to_name = dict(zip(country_codes["country_code"], country_codes["country_name"]))

# ── Process each year ──────────────────────────────────────────
all_frames = []
years = list(range(2012, 2025))   # BACI HS12 covers 2012–2024

print(f"Reading {len(years)} BACI files from: {BACI_DIR}\n")
t0 = time.time()

for yr in years:
    fname = f"BACI_HS12_Y{yr}_V202601.csv"
    fpath = os.path.join(BACI_DIR, fname)

    if not os.path.exists(fpath):
        print(f"  [{yr}] NOT FOUND — skipping: {fname}")
        continue

    print(f"  [{yr}] Reading...", end=" ", flush=True)
    t_yr = time.time()

    # Read the full file — BACI uses: t,i,j,k,v,q
    df = pd.read_csv(fpath, dtype={"k": str})

    # Filter to our 7 HS codes only
    df = df[df["k"].isin(HS_LAYER.keys())].copy()
    print(f"{len(df):,} rows after filter", end=" | ", flush=True)

    # Assign layer
    df["layer"] = df["k"].map(HS_LAYER)

    # Merge exporter and importer ISO3 + names
    df["iso3_exp"] = df["i"].map(code_to_iso3)
    df["iso3_imp"] = df["j"].map(code_to_iso3)
    df["country_exp"] = df["i"].map(code_to_name)
    df["country_imp"] = df["j"].map(code_to_name)

    # Convert value to USD (BACI stores in USD thousands)
    df["value_usd"] = df["v"] * 1000

    # Drop rows with missing country codes (unclassified territories)
    before = len(df)
    df = df.dropna(subset=["iso3_exp", "iso3_imp"])
    dropped = before - len(df)
    if dropped > 0:
        print(f"(dropped {dropped} rows with unknown country codes)", end=" | ")

    print(f"Done in {time.time()-t_yr:.1f}s")
    all_frames.append(df)

# ── Combine all years ──────────────────────────────────────────
print(f"\nCombining {len(all_frames)} year-files...")
baci = pd.concat(all_frames, ignore_index=True)

# Rename columns for clarity
baci = baci.rename(columns={"t": "year", "k": "hs6", "v": "value_kusd", "q": "quantity"})

# Select and reorder columns
baci = baci[["year","hs6","layer","i","j","iso3_exp","country_exp",
             "iso3_imp","country_imp","value_kusd","value_usd","quantity"]]

# ── Save ───────────────────────────────────────────────────────
out_path = os.path.join(OUTPUT_DIR, "01_baci_ree_filtered.csv")
baci.to_csv(out_path, index=False)

print(f"\n✓ Saved: {out_path}")
print(f"  Total rows : {len(baci):,}")
print(f"  Years      : {baci['year'].min()} – {baci['year'].max()}")
print(f"  HS codes   : {sorted(baci['hs6'].unique())}")
print(f"  Exporters  : {baci['iso3_exp'].nunique()} countries")
print(f"  Importers  : {baci['iso3_imp'].nunique()} countries")
print(f"  Total time : {time.time()-t0:.0f}s")
print(f"\n→ NEXT: run  Step2_Build_Networks.py")
