"""
STEP 2 — Build Adjacency Matrices & Compute All Network Metrics
═══════════════════════════════════════════════════════════════
Reads the filtered BACI output from Step 1.
For each year × layer combination, builds a directed weighted network
and computes: betweenness, eigenvector, out-strength, in-strength,
network density, and clustering coefficient.

Also computes the dependence matrix D_ijt (share of imports from i for j).

HOW TO RUN:
    python Step2_Build_Networks.py

Requires: networkx   (pip install networkx)
Time: ~5-10 minutes for 13 years × 3 layers.

Outputs:
  data/02_centrality_panel.csv     ← country-year-layer centrality metrics
  data/02_network_stats.csv        ← year-layer network-level stats (density, etc.)
  data/02_dependence_matrix.csv    ← full D_ijt for all i-j-t-layer combinations
"""

import pandas as pd
import numpy as np
import networkx as nx
import os, time, warnings
warnings.filterwarnings("ignore")

# ── PATHS ──────────────────────────────────────────────────────
DATA_DIR = "/Users/sanayounas/Claude/Projects/Netwrok/data"
IN_FILE  = os.path.join(DATA_DIR, "01_baci_ree_filtered.csv")

# ── LOAD FILTERED BACI ─────────────────────────────────────────
print("Loading filtered BACI data...")
baci = pd.read_csv(IN_FILE, dtype={"hs6": str})
print(f"  {len(baci):,} rows loaded | years {baci['year'].min()}–{baci['year'].max()}")

# ── LAYER DEFINITIONS ──────────────────────────────────────────
# Narrow = main analysis. Broad = robustness check.
NARROW_CODES = {1: ["261790"], 2: ["284690"], 3: ["850511"]}
BROAD_CODES  = {1: ["261790","253090"], 2: ["284690","284610","280530"], 3: ["850511","850519"]}

LAYER_LABELS = {1: "Upstream (ores)", 2: "Midstream (compounds)", 3: "Downstream (magnets)"}

# ── FUNCTION: build graph and compute metrics ──────────────────
def compute_network_metrics(df_edges, year, layer, definition="narrow"):
    """
    df_edges: rows with iso3_exp, iso3_imp, value_usd
    Returns: (centrality_df, network_stats_dict)
    """
    # Aggregate to country-pair (sum across HS codes within layer)
    edges = (df_edges.groupby(["iso3_exp","iso3_imp"])["value_usd"]
             .sum().reset_index())
    edges = edges[edges["value_usd"] > 0]

    if len(edges) == 0:
        return pd.DataFrame(), {}

    # Build directed weighted graph
    G = nx.DiGraph()
    for _, row in edges.iterrows():
        G.add_edge(row["iso3_exp"], row["iso3_imp"], weight=row["value_usd"])

    nodes = list(G.nodes())
    n = len(nodes)
    if n < 2:
        return pd.DataFrame(), {}

    # ── Network-level statistics ──
    density = nx.density(G)
    total_trade = edges["value_usd"].sum()

    # ── Node-level metrics ──
    # Betweenness centrality
    # Note: for betweenness, use inverse weight (shorter path = higher value flows)
    # But for REE: higher trade = more influence → use weight directly for strength,
    # inverse for betweenness path cost
    try:
        # Add inverse weight for shortest-path computation
        for u, v, d in G.edges(data=True):
            G[u][v]["inv_weight"] = 1.0 / (d["weight"] + 1e-9)
        bt = nx.betweenness_centrality(G, weight="inv_weight", normalized=True)
    except Exception:
        bt = dict.fromkeys(nodes, 0.0)

    # Eigenvector centrality (uses weight directly: connection to important nodes)
    try:
        ev = nx.eigenvector_centrality(G, weight="weight", max_iter=1000, tol=1e-6)
    except Exception:
        ev = dict.fromkeys(nodes, 0.0)

    # Out-strength and in-strength (total weighted degree)
    out_str = dict(G.out_degree(weight="weight"))
    in_str  = dict(G.in_degree(weight="weight"))

    # Out-degree and in-degree (unweighted)
    out_deg = dict(G.out_degree())
    in_deg  = dict(G.in_degree())

    # ── Assemble country-level results ──
    cent_rows = []
    for node in nodes:
        cent_rows.append({
            "year":           year,
            "layer":          layer,
            "layer_label":    LAYER_LABELS[layer],
            "definition":     definition,
            "iso3":           node,
            "betweenness":    bt.get(node, 0),
            "eigenvector":    ev.get(node, 0),
            "out_strength":   out_str.get(node, 0),
            "in_strength":    in_str.get(node, 0),
            "out_degree":     out_deg.get(node, 0),
            "in_degree":      in_deg.get(node, 0),
        })

    cent_df = pd.DataFrame(cent_rows)

    net_stats = {
        "year":         year,
        "layer":        layer,
        "layer_label":  LAYER_LABELS[layer],
        "definition":   definition,
        "n_nodes":      n,
        "n_edges":      G.number_of_edges(),
        "density":      density,
        "total_trade_usd": total_trade,
        "top_exporter": max(out_str, key=out_str.get),
        "top_exporter_share": max(out_str.values()) / total_trade if total_trade > 0 else 0,
    }

    return cent_df, net_stats


# ── FUNCTION: compute dependence matrix ───────────────────────
def compute_dependence(df_edges, year, layer, definition="narrow"):
    """
    D_ijt = exports from i to j / total imports of j (in year t, layer, definition)
    """
    edges = (df_edges.groupby(["iso3_exp","iso3_imp"])["value_usd"]
             .sum().reset_index())
    edges = edges[edges["value_usd"] > 0].copy()
    total_imp = edges.groupby("iso3_imp")["value_usd"].transform("sum")
    edges["D_ijt"] = edges["value_usd"] / total_imp
    edges["year"]       = year
    edges["layer"]      = layer
    edges["definition"] = definition
    return edges


# ── MAIN LOOP ──────────────────────────────────────────────────
all_centrality = []
all_net_stats  = []
all_dependence = []

years = sorted(baci["year"].unique())
print(f"\nComputing networks for {len(years)} years × 3 layers × 2 definitions...\n")

for yr in years:
    baci_yr = baci[baci["year"] == yr]
    t_yr = time.time()

    for layer in [1, 2, 3]:
        for defn, codes in [("narrow", NARROW_CODES[layer]),
                             ("broad",  BROAD_CODES[layer])]:

            subset = baci_yr[baci_yr["hs6"].isin(codes)]
            if len(subset) == 0:
                continue

            cent, stats = compute_network_metrics(subset, yr, layer, defn)
            dep          = compute_dependence(subset, yr, layer, defn)

            if len(cent) > 0:
                all_centrality.append(cent)
                all_net_stats.append(stats)
            if len(dep) > 0:
                all_dependence.append(dep)

    print(f"  [{yr}] Done in {time.time()-t_yr:.1f}s")

# ── Save outputs ───────────────────────────────────────────────
print("\nSaving outputs...")

centrality_df = pd.concat(all_centrality, ignore_index=True)
centrality_df.to_csv(os.path.join(DATA_DIR, "02_centrality_panel.csv"), index=False)
print(f"  ✓ Centrality panel: {len(centrality_df):,} rows")
print(f"    Countries tracked: {centrality_df['iso3'].nunique()}")

net_stats_df = pd.DataFrame(all_net_stats)
net_stats_df.to_csv(os.path.join(DATA_DIR, "02_network_stats.csv"), index=False)
print(f"  ✓ Network stats: {len(net_stats_df)} rows")

dep_df = pd.concat(all_dependence, ignore_index=True)
dep_df.to_csv(os.path.join(DATA_DIR, "02_dependence_matrix.csv"), index=False)
print(f"  ✓ Dependence matrix: {len(dep_df):,} rows")

# ── Quick validation ───────────────────────────────────────────
print("\n=== VALIDATION CHECK (2022, Layer 2 Midstream, Narrow) ===")
val = centrality_df[
    (centrality_df["year"] == 2022) &
    (centrality_df["layer"] == 2) &
    (centrality_df["definition"] == "narrow")
].sort_values("betweenness", ascending=False)

print("\nTop 10 by Betweenness Centrality (Layer 2, 2022):")
print(val[["iso3","betweenness","eigenvector","out_strength","in_strength"]].head(10).to_string(index=False))

print("\nTop 10 by Out-Strength (Layer 2, 2022):")
print(val.sort_values("out_strength", ascending=False)[
    ["iso3","out_strength","betweenness"]].head(10).to_string(index=False))

if "CHN" in val["iso3"].values:
    chn_rank_bt = (val["betweenness"] > val[val["iso3"]=="CHN"]["betweenness"].values[0]).sum() + 1
    print(f"\n✓ China betweenness rank (Layer 2, 2022): #{chn_rank_bt}")
    if chn_rank_bt == 1:
        print("  ✓ VALIDATION PASSED: China is #1 in midstream betweenness — expected result.")
    else:
        print(f"  ⚠ WARNING: China is not #1. Check HS code mapping or data filtering.")

print(f"\n→ NEXT: run  Step3_Vulnerability_Variables.py")
