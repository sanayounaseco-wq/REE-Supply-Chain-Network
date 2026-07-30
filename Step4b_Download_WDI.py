"""
STEP 4b — Download World Bank WDI Data (GDP + Controls)
════════════════════════════════════════════════════════
Downloads GDP and manufacturing data for all countries, 2012–2024,
from the World Bank API. Takes ~2 minutes.

HOW TO RUN:
    python Step4b_Download_WDI.py

Output: data/04b_wdi_panel.csv  (merged back into master panel automatically)
"""

import requests
import pandas as pd
import os, time

DATA_DIR = "/Users/sanayounas/Claude/Projects/Netwrok/data"
os.makedirs(DATA_DIR, exist_ok=True)

BASE_URL = "https://api.worldbank.org/v2/country/all/indicator/{indicator}"
PARAMS_BASE = {"format": "json", "per_page": 10000, "mrv": 20}

INDICATORS = {
    "NY.GDP.MKTP.CD":  "gdp_current_usd",
    "NY.GDP.PCAP.CD":  "gdp_per_capita",
    "NV.IND.MANF.ZS":  "manufacturing_share_gdp",
    "SP.POP.TOTL":     "population",
}

def fetch_indicator(code, label):
    url = BASE_URL.format(indicator=code)
    params = {**PARAMS_BASE, "date": "2012:2024"}
    try:
        r = requests.get(url, params=params, timeout=30)
        raw = r.json()
        if len(raw) < 2 or raw[1] is None:
            print(f"  ✗ {label}: no data returned")
            return pd.DataFrame()
        records = []
        for entry in raw[1]:
            if entry.get("value") is not None:
                records.append({
                    "iso3": entry["countryiso3code"],
                    "year": int(entry["date"]),
                    label: entry["value"]
                })
        df = pd.DataFrame(records)
        df = df[df["iso3"].str.len() == 3]   # drop aggregate regions
        print(f"  ✓ {label}: {len(df):,} rows ({df['iso3'].nunique()} countries)")
        return df
    except Exception as e:
        print(f"  ✗ {label}: {e}")
        return pd.DataFrame()

print("Downloading World Bank WDI data (2012–2024)...\n")

frames = []
for code, label in INDICATORS.items():
    df = fetch_indicator(code, label)
    if not df.empty:
        frames.append(df)
    time.sleep(0.5)   # polite pause between API calls

if not frames:
    print("\n✗ Could not reach World Bank API.")
    print("  Try running this from your terminal (check internet connection).")
    raise SystemExit(1)

# Merge all indicators on iso3 + year
print("\nMerging indicators...")
wdi = frames[0]
for df in frames[1:]:
    wdi = wdi.merge(df, on=["iso3","year"], how="outer")

wdi = wdi.sort_values(["iso3","year"]).reset_index(drop=True)
out_path = os.path.join(DATA_DIR, "04b_wdi_panel.csv")
wdi.to_csv(out_path, index=False)

print(f"\n✓ Saved: {out_path}")
print(f"  Rows: {len(wdi):,} | Countries: {wdi['iso3'].nunique()} | "
      f"Years: {wdi['year'].min()}–{wdi['year'].max()}")

# ── Merge WDI back into master panel ──────────────────────────
master_path = os.path.join(DATA_DIR, "04_master_panel.csv")
if os.path.exists(master_path):
    print("\nMerging WDI into master panel...")
    master = pd.read_csv(master_path)

    # Drop old approximate GDP column
    master = master.drop(columns=["gdp_current_usd","gdp_note"], errors="ignore")

    # Merge real WDI data
    master = master.merge(wdi, on=["iso3","year"], how="left")
    master.to_csv(master_path, index=False)

    print(f"  ✓ Master panel updated: {len(master):,} rows")
    print(f"  Columns with WDI data: {[c for c in wdi.columns if c not in ['iso3','year']]}")

    # Coverage check — handle case where API returned no GDP rows
    if "gdp_current_usd" in master.columns:
        gdp_coverage = master["gdp_current_usd"].notna().sum()
        print(f"  GDP coverage: {gdp_coverage:,} / {len(master):,} rows "
              f"({gdp_coverage/len(master)*100:.0f}%)")
    else:
        print("  ⚠ gdp_current_usd not in merged panel — WDI GDP indicator may not have downloaded.")
        print(f"  Available WDI columns: {[c for c in master.columns if c in wdi.columns]}")

print("\n→ NEXT: run  Step5_Regressions.py")
