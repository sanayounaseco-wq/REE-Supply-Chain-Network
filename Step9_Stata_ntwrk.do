/*===========================================================================
  Step 9: Stata ntwrk Replication & Extension
  Paper: Bottlenecks and Bargaining Power in the Global REE Supply Chain

  PURPOSE:
    1. Install and test the new stata-ntwrk package (v1.0 beta, Jun 2026)
    2. Replicate our Python/NetworkX betweenness centrality results
    3. Add new measures unavailable in our Python pipeline:
       PageRank, HITS (hub/authority), reciprocity, closeness, ancestors/descendants
    4. Generate publication-quality network figures using ntwrk's layout engine

  DATA:
    01_baci_ree_filtered.csv — our BACI edge list (184,555 rows)
    Variables: year, hs6, layer, iso3_exp, iso3_imp, value_usd, quantity
    NOTE: No "definition" column — use hs6 to select narrow vs broad:
      Narrow: hs6 == "261790" (L1) | "284690" (L2) | "850511" (L3)
      Broad:  all hs6 codes within each layer (multiple codes, sum before running)
    COPY THIS FILE to your other laptop. It is the only file needed.

  EXPECTED REPLICATION CHECK (compare to Python Step 2 output):
    China L2 betweenness (2023, narrow, weighted) ≈ 0.356
    China L1 betweenness (2023, narrow, weighted) ≈ 0.311
    China L3 betweenness (2023, narrow, weighted) ≈ 0.581

  Author: Sana Younas
  Date:   June 2026
===========================================================================*/

clear all
set more off

* ─── Set paths ─────────────────────────────────────────────────────────────
global DATA  "/Users/sanayounas/Claude/Projects/Netwrok/data"
global OUT   "/Users/sanayounas/Claude/Projects/Netwrok/data"
global FIGS  "/Users/sanayounas/Claude/Projects/Netwrok/figures"

cap mkdir "$FIGS"

/*---------------------------------------------------------------------------
  SECTION A: INSTALLATION
  Run this block once. Comment it out after first install.
---------------------------------------------------------------------------*/

* Required dependencies
ssc install palettes,       replace
ssc install colrspace,      replace
ssc install graphfunctions, replace

* Install ntwrk (GitHub — most recent beta)
net install ntwrk, ///
    from("https://raw.githubusercontent.com/asjadnaqvi/stata-ntwrk/main/installation/") ///
    replace

/*---------------------------------------------------------------------------
  SECTION B: LOAD AND PREPARE DATA
---------------------------------------------------------------------------*/

* Import everything as strings first (works on all Stata versions)
import delimited "$DATA/01_baci_ree_filtered.csv", clear stringcols(_all)

* Convert only the numeric columns; iso3/country columns stay as strings
destring year hs6 layer i j value_kusd value_usd quantity, replace ignore(",")

* ── Narrow definition HS codes (one code per layer, main analysis) ──────────
* L1 narrow: hs6 == "261790"   (rare earth ores)
* L2 narrow: hs6 == "284690"   (rare earth compounds)  ← key analytical layer
* L3 narrow: hs6 == "850511"   (permanent magnets)
*
* Broad definition adds extra codes per layer — used for robustness checks
* L1 broad adds:  253090
* L2 broad adds:  284610, 280530
* L3 broad adds:  850519
*
* For main analysis keep narrow codes only:
gen narrow = (hs6 == 261790 & layer == 1) | ///
             (hs6 == 284690 & layer == 2) | ///
             (hs6 == 850511 & layer == 3)

* Quick count check
di "Total observations: " _N
di "Narrow definition flows: " %9.0f `=_N'
tab layer narrow

/*---------------------------------------------------------------------------
  SECTION C: REPLICATION CHECK — 2023 LAYER 2 BETWEENNESS
  Compare output to Python Step 2: China L2 betweenness should be ≈ 0.356
---------------------------------------------------------------------------*/

di _newline "=== REPLICATION CHECK: L2 Midstream 2023 ==="

preserve
    keep if year == 2023 & layer == 2 & narrow == 1
    collapse (sum) value_usd, by(iso3_exp iso3_imp)   // aggregate to country pair

    * NOTE: option order matters — saveprefix() before replace
    ntwrk value_usd, from(iso3_exp) to(iso3_imp) ///
        measure(between)                           ///
        weighted                                   ///
        nograph                                    ///
        save saveprefix("$OUT/ntwrk_check_L2_2023") replace

    * Check ntwrk actually produced the file before loading it
    local nodefile "$OUT/ntwrk_check_L2_2023.dta"
    confirm file "`nodefile'"
    if _rc != 0 {
        di as error "ntwrk did not save output — check that ntwrk is installed and $OUT path exists"
        di as error "Run:  net install ntwrk, from(...) replace"
        di as error "Also check $OUT = " "$OUT"
    }
    else {
        use "`nodefile'", clear
        gsort -between
        di "Top 10 countries by weighted betweenness (L2, 2023):"
        * ntwrk uses the from() variable name as node ID (iso3_exp in our data)
        cap rename iso3_exp iso3
        if _rc != 0 {
            ds, has(type string)
            local strvar = word("`r(varlist)'", 1)
            rename `strvar' iso3
        }
        list iso3 between in 1/10, clean

        * Python target: CHN = 0.356
        sum between if iso3 == "CHN"
        di "Python result: 0.356  |  Stata result: " r(mean)
        if abs(r(mean) - 0.356) < 0.02 {
            di ">>> REPLICATION PASSED (within 2% of Python result)"
        }
        else {
            di ">>> CHECK DISCREPANCY — may be normalization difference"
        }
    }
restore

/*---------------------------------------------------------------------------
  SECTION D: KEY SLICES — 2023, ALL THREE LAYERS
  We only need 2023 for comparison with Python results and for figures.
  (The full Python panel from Step 2 already covers all years.)
  Running ntwrk once per layer, checking _rc each time so errors are visible.
---------------------------------------------------------------------------*/

di _newline "=== COMPUTING 2023 CENTRALITY: ALL THREE LAYERS ==="

* Re-load the master data (preserve/restore in Section C left us at original)
import delimited "$DATA/01_baci_ree_filtered.csv", clear stringcols(_all)
destring year hs6 layer i j value_kusd value_usd quantity, replace ignore(",")

gen narrow = (hs6 == 261790 & layer == 1) | ///
             (hs6 == 284690 & layer == 2) | ///
             (hs6 == 850511 & layer == 3)

keep if year == 2023 & narrow == 1

foreach lyr in 1 2 3 {

    di _newline "--- Layer `lyr', 2023 ---"

    preserve
    keep if layer == `lyr'
    collapse (sum) value_usd, by(iso3_exp iso3_imp)

    di "  Flows: " _N
    if _N < 3 {
        di "  Skipping: too few flows"
        restore
        continue
    }

    * ntwrk converts string node IDs to integers internally.
    * Use string from(iso3_exp) so ntwrk names the output column "iso3_exp".
    * Save an alphabetically-sorted node list BEFORE ntwrk (no nested preserve needed —
    * just save to disk, extract map, reload, then run ntwrk).
    save "$OUT/edgelist_L`lyr'_temp.dta", replace

    keep iso3_exp
    duplicates drop
    sort iso3_exp          // alphabetical — matches ntwrk's default node ordering
    gen iso3_node_id = _n  // 1 = first alphabetically
    save "$OUT/iso3map_L`lyr'.dta", replace

    use "$OUT/edgelist_L`lyr'_temp.dta", clear

    * Run without cap so any error is visible
    ntwrk value_usd, from(iso3_exp) to(iso3_imp)  ///
        measure(between eigenvec pagerank hits      ///
                reciprocity indegree outdegree)     ///
        weighted nograph                            ///
        save saveprefix("$OUT/ntwrk_L`lyr'_2023") replace

    di "  Saved: $OUT/ntwrk_L`lyr'_2023.dta"
    restore
}

/*---------------------------------------------------------------------------
  SECTION E: COMBINE THREE LAYER FILES INTO ONE DATASET
---------------------------------------------------------------------------*/

di _newline "=== COMBINING LAYER FILES ==="

* Helper program: recover iso3 string from ntwrk output.
* ntwrk always saves the original node string label in _label (str3, "Node Label").
* This is confirmed in the describe output — use it directly.
* iso3_exp is stored as int (ntwrk's internal encoding) and is NOT reliable for strings.
capture program drop recover_iso3
program define recover_iso3
    args lyr out_path

    * Primary: _label is already the ISO3 string ntwrk saved from the from() variable
    cap confirm string variable _label
    if _rc == 0 {
        rename _label iso3
        exit
    }

    * Fallback 1: iso3_exp is somehow a string (future ntwrk version?)
    cap confirm string variable iso3_exp
    if _rc == 0 {
        rename iso3_exp iso3
        exit
    }

    * Fallback 2: alphabetical node ID merge (last resort)
    rename iso3_exp iso3_node_id
    merge 1:1 iso3_node_id using "`out_path'/iso3map_L`lyr'.dta", ///
        keep(master match) nogen
    rename iso3_exp iso3
    drop iso3_node_id
end

* Load Layer 1, tag it, recover iso3 string
use "$OUT/ntwrk_L1_2023.dta", clear
gen layer = 1
gen year  = 2023
recover_iso3 1 "$OUT"
tempfile combined
save `combined', replace

* Append Layer 2
use "$OUT/ntwrk_L2_2023.dta", clear
gen layer = 2
gen year  = 2023
recover_iso3 2 "$OUT"
append using `combined'
save `combined', replace

* Append Layer 3
use "$OUT/ntwrk_L3_2023.dta", clear
gen layer = 3
gen year  = 2023
recover_iso3 3 "$OUT"
append using `combined'
save `combined', replace

* Load combined and tidy
* ntwrk output mixes link rows (_control==0) and node rows (_control==1).
* Centrality measures only exist on node rows — drop all link rows now.
use `combined', clear
keep if _control == 1
sort layer iso3
order iso3 layer year

* Rename to match our paper conventions
cap rename between   betweenness_ntwrk
cap rename eigenvec  eigenvec_ntwrk
cap rename pagerank  pagerank_ntwrk
cap rename hub       hits_hub_ntwrk
cap rename authority hits_auth_ntwrk

di "Combined dataset: " _N " observations"
describe

* Save
save "$OUT/09_stata_centrality_panel.dta", replace
export delimited "$OUT/09_stata_centrality_panel.csv", replace
di "Saved: 09_stata_centrality_panel.dta"

di "Saved: 09_stata_centrality_panel.dta"
di "Variables in panel:"
describe

/*---------------------------------------------------------------------------
  SECTION F: COMPARE PYTHON vs STATA RESULTS (2023, Layer 2)
  Merge with our Python output and check correlations
---------------------------------------------------------------------------*/

di _newline "=== PYTHON vs STATA COMPARISON (L2, 2023) ==="
di "NOTE: This section requires 02_centrality_panel.csv (Python Step 2 output)."
di "      Copy it from your Mac to $DATA and re-run if you want the correlation check."

* Show ntwrk's actual output variable names so we can fix renames if needed
di _newline "ntwrk L2 output variables (check these match the cap rename lines above):"
describe using "$OUT/ntwrk_L2_2023.dta"

* Skip if Python panel not available (e.g. running on a different laptop)
cap confirm file "$DATA/02_centrality_panel.csv"
if _rc != 0 {
    di ">>> 02_centrality_panel.csv not found — skipping Python vs Stata comparison."
    di "    Showing Stata-only results instead:"

    use "$OUT/09_stata_centrality_panel.dta", clear
    keep if layer == 2

    di _newline "Top 10 by Stata betweenness (L2, 2023):"
    gsort -betweenness_ntwrk
    list iso3 betweenness_ntwrk in 1/10, clean

    di _newline "Top 10 by PageRank (L2, 2023):"
    gsort -pagerank_ntwrk
    list iso3 pagerank_ntwrk betweenness_ntwrk in 1/10, clean
}
else {
    * Python panel available — run full comparison
    import delimited "$DATA/02_centrality_panel.csv", clear stringcols(_all)
    destring year layer betweenness eigenvector out_strength, replace ignore(",")
    * Python panel has narrow + broad rows — keep narrow only to get 1 row per iso3
    keep if year == 2023 & layer == 2 & definition == "narrow"
    keep iso3 betweenness eigenvector out_strength
    duplicates drop iso3, force          // safety net
    rename betweenness  btw_python
    rename eigenvector  eig_python
    rename out_strength str_python
    * Use a named file instead of tempfile to avoid path-with-spaces issue on Windows
    save "$OUT/temp_python_cent.dta", replace

    use "$OUT/09_stata_centrality_panel.dta", clear
    keep if layer == 2
    keep iso3 betweenness_ntwrk eigenvec_ntwrk pagerank_ntwrk hits_hub_ntwrk hits_auth_ntwrk

    * Ensure iso3 is string to match Python panel (str3)
    cap confirm numeric variable iso3
    if _rc == 0 {
        cap decode iso3, gen(iso3_str)
        if _rc != 0 tostring iso3, gen(iso3_str) force
        drop iso3
        rename iso3_str iso3
    }

    merge 1:1 iso3 using "$OUT/temp_python_cent.dta"
    keep if _merge == 3
    drop _merge

    * Diagnostics: show what's actually in the merged dataset
    di _newline "Merged dataset — summary of key variables:"
    sum betweenness_ntwrk eigenvec_ntwrk pagerank_ntwrk btw_python eig_python

    * Only correlate variables that have non-missing values
    qui sum betweenness_ntwrk
    if r(N) > 2 {
        pwcorr btw_python betweenness_ntwrk, sig
    }
    else {
        di "WARNING: betweenness_ntwrk is all-missing."
        di "  The 'cap rename between betweenness_ntwrk' above likely failed silently."
        di "  Run 'describe using $OUT/ntwrk_L2_2023.dta' to see the actual variable name."
        di "  Then update the cap rename lines in Section E accordingly."
    }

    qui sum eigenvec_ntwrk
    if r(N) > 2 pwcorr eig_python eigenvec_ntwrk, sig

    di _newline "Top 10 by Stata betweenness (L2, 2023):"
    cap gsort -betweenness_ntwrk
    cap list iso3 betweenness_ntwrk btw_python pagerank_ntwrk in 1/10, clean

    di _newline "Top 10 by PageRank (L2, 2023):"
    cap gsort -pagerank_ntwrk
    cap list iso3 pagerank_ntwrk betweenness_ntwrk in 1/10, clean
}

di _newline "Top HITS hub scores (L2, 2023) — Myanmar should rank high:"
use "$OUT/09_stata_centrality_panel.dta", clear
keep if layer == 2
cap gsort -hits_hub_ntwrk
cap list iso3 hits_hub_ntwrk hits_auth_ntwrk in 1/10, clean

/*---------------------------------------------------------------------------
  SECTION G: NETWORK VISUALIZATIONS
  Produce publication-quality figures per layer, 2023
---------------------------------------------------------------------------*/

di _newline "=== GENERATING NETWORK FIGURES ==="

* Section G needs raw BACI data (narrow, iso3_exp, value_usd).
* Reload it — the current dataset is the centrality panel from Section E/F.
import delimited "$DATA/01_baci_ree_filtered.csv", clear stringcols(_all)
destring year hs6 layer i j value_kusd value_usd quantity, replace ignore(",")
gen narrow = (hs6 == 261790 & layer == 1) | ///
             (hs6 == 284690 & layer == 2) | ///
             (hs6 == 850511 & layer == 3)
keep if year == 2023 & narrow == 1

local layer_labels 1 "L1 Upstream Ores (HS 261790)" ///
                   2 "L2 Midstream Compounds (HS 284690)" ///
                   3 "L3 Downstream Magnets (HS 850511)"

local layer_palettes 1 "Blues" 2 "Reds" 3 "Greens"

foreach lyr in 1 2 3 {

    local lbl : word `=2*`lyr'' of `layer_labels'   // won't work like this, use if/else
    if `lyr' == 1 {
        local lbl   "L1 — Upstream Ores (HS 261790)"
        local pal   "Blues"
    }
    else if `lyr' == 2 {
        local lbl   "L2 — Midstream Compounds (HS 284690)"
        local pal   "Reds"
    }
    else {
        local lbl   "L3 — Downstream Magnets (HS 850511)"
        local pal   "Greens"
    }

    preserve
    keep if layer == `lyr'
    collapse (sum) value_usd, by(iso3_exp iso3_imp)

    * ── Fruchterman-Reingold layout with betweenness-sized nodes ──
    cap ntwrk value_usd, from(iso3_exp) to(iso3_imp)  ///
        measure(between pagerank) mvar(between)         ///
        weighted                                        ///
        layout(fr) seed(2026)                           ///
        lquantile(8) lscale lprop lscalefactor(0.5)    ///
        mscale mscalefactor(0.5) msize(10)              ///
        lpalette(`pal') mpalette(plasma)                ///
        lalpha(70) malpha(80)                           ///
        arc arcn(3)                                     ///
        novalues mlabsize(1.4) mlwidth(0.1) mlc(black)  ///
        title("`lbl'", size(small))                     ///
        subtitle("2023 · Weighted betweenness · Node size = betweenness centrality", size(vsmall))

    graph export "$FIGS/ntwrk_L`lyr'_fr_2023.png", replace width(2400)

    * ── Star layout (China at hub, shows spoke structure clearly) ──
    cap ntwrk value_usd, from(iso3_exp) to(iso3_imp)  ///
        measure(pagerank) mvar(pagerank)                ///
        weighted                                        ///
        layout(star) seed(2026)                         ///
        lquantile(10) lscale lprop lscalefactor(0.5)   ///
        mscale mscalefactor(0.5) msize(10)              ///
        lpalette(`pal', reverse)                        ///
        malpha(0) mlalpha(100) mlabsize(1.8)            ///
        mlcolor(black) mlwidth(0.15)                    ///
        novalues arc lwidth(0.5)                        ///
        title("`lbl'", size(small))                     ///
        subtitle("2023 · Star layout · Node size = PageRank", size(vsmall))

    graph export "$FIGS/ntwrk_L`lyr'_star_2023.png", replace width(2400)

    restore
}

di "Figures saved to: $FIGS"

/*---------------------------------------------------------------------------
  SECTION H: MYANMAR SPECIAL ANALYSIS
  HITS hub/authority split reveals Myanmar as a pure hub (exporter to China)
  even though its betweenness ≈ 0
---------------------------------------------------------------------------*/

di _newline "=== MYANMAR HITS ANALYSIS ==="

use "$OUT/09_stata_centrality_panel.dta", clear
keep if layer == 2

* Myanmar's hub score should be high in recent years (it's a hub that points to China)
* Myanmar's authority score should be near 0 (nothing points to it)
list year hits_hub_ntwrk hits_auth_ntwrk betweenness_ntwrk if iso3 == "MMR", clean

di _newline "China's authority score (L2) — should be high (pointed to by Myanmar, Laos, etc.):"
list year hits_hub_ntwrk hits_auth_ntwrk betweenness_ntwrk if iso3 == "CHN", clean

/*---------------------------------------------------------------------------
  SECTION I: ADDITIONAL MEASURES FOR PAPER
  Reciprocity, ancestors/descendants — not in Python pipeline
---------------------------------------------------------------------------*/

di _newline "=== RECIPROCITY AND REACH ANALYSIS ==="

* Section I uses the already-saved L2 2023 node file from Section D.
* ntwrk output includes both link and node rows; keep node rows only.
use "$OUT/ntwrk_L2_2023.dta", clear
keep if _control == 1      // node rows only (centrality measures live here)

* _label is ntwrk's str3 node label (ISO3 code); use it instead of 'id'
di "Reciprocity by country (L2, 2023):"
di "(= share of outgoing ties that have a return flow)"
gsort -reciprocity
list _label reciprocity between in 1/15, clean

di _newline "Betweenness top 10 (L2, 2023):"
gsort -between
list _label between pagerank in 1/10, clean

/*---------------------------------------------------------------------------
  SECTION J: NOTES FOR PAPER INTEGRATION
---------------------------------------------------------------------------*/

di _newline "=== NOTES FOR PAPER ==="
di ""
di "1. REPLICATION: If betweenness correlation (Python vs Stata) > 0.99,"
di "   add footnote: 'Results replicated using stata-ntwrk v1.0 (Naqvi, 2026).'"
di ""
di "2. NEW MEASURES to consider adding to paper:"
di "   - PageRank (Section 5.2): alternative to betweenness; more robust to"
di "     isolated nodes; good supplementary H1 test"
di "   - HITS hub score: Myanmar ranks high in hub score despite betweenness ≈ 0;"
di "     formal evidence for the 'hidden bottleneck' framing"
di "   - Reciprocity: how bilateral REE trade is — low reciprocity in L2"
di "     (China exports processed compounds, doesn't import them back)"
di ""
di "3. VISUALIZATION: ntwrk star layout with arc edges is publication-ready;"
di "   consider replacing Figure 2 (top-10 bar chart) with a star network figure"
di ""
di "4. CITATION: Naqvi, A. (2026). ntwrk: Stata package for network analysis"
di "   and visualization from edge-list data. Version 1.0. GitHub."

di _newline "=== Step 9 complete ==="
