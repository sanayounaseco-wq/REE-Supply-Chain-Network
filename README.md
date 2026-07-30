[README.txt](https://github.com/user-attachments/files/30536728/README.txt)
# REE-Supply-Chain-NetworkREADME — Replication Files
==========================
Paper: "Hidden Bottlenecks in the Rare Earth Supply Chain: Myanmar,
        China's Processing Hub, and Multilayer Network Vulnerability"
Author: Sana Younas, University of Portsmouth
Submitted to: Energy Policy, July 2026

--------------------------------------------------------------------
RAW DATA — DOWNLOAD REQUIRED
--------------------------------------------------------------------
This repository does NOT include the raw BACI trade data (several GB).
Download BACI HS12 V202601 (2012–2024) from CEPII before running Step 1:

  https://www.cepii.fr/CEPII/en/bdd_modele/bdd_modele_item.asp?id=37

Unzip all year files into one folder (e.g. /Downloads/BACI_HS12_V202601/).
Then update the BACI_DIR path at the top of Step1_Filter_BACI.py.

--------------------------------------------------------------------
SOFTWARE REQUIREMENTS
--------------------------------------------------------------------
Python 3.9+
  pip install pandas networkx matplotlib scipy requests openpyxl

Stata 17+ (for regression and ntwrk replication steps)
  - reghdfe   (ssc install reghdfe)
  - ftools    (ssc install ftools)
  - estout    (ssc install estout)
  - stata-ntwrk v1.0 (github.com/asjadnaqvi/stata-ntwrk)

--------------------------------------------------------------------
PIPELINE — RUN IN ORDER
--------------------------------------------------------------------

STEP 1  Step1_Filter_BACI.py
  Reads BACI year-files, keeps 7 REE HS codes, assigns supply-chain
  layers (L1=ores, L2=compounds, L3=magnets), saves filtered CSV.
  Output: data/01_baci_ree_filtered.csv
  Time:   ~3–5 minutes

STEP 2  Step2_Build_Networks.py
  Builds directed weighted networks for each year × layer.
  Computes betweenness centrality (inverse-weight shortest paths),
  dependence matrices D_ijt, and network-level statistics.
  Output: data/02_centrality_panel.csv
          data/02_dependence_matrix.csv
          data/02_network_stats.csv
  Time:   ~5–10 minutes

STEP 3  Step3_Vulnerability_Variables.py
  Computes all regression variables: China import share, HHI,
  supplier count, dependent importers (25% and 50% thresholds),
  Supply Vulnerability Index (SVI), alliance diversity index (AllyDiv),
  MSP membership binary, export restriction binary.
  Output: data/03_vulnerability_panel.csv

STEP 4b Step4b_Download_WDI.py
  Downloads GDP (World Development Indicators) via World Bank API.
  Output: data/04b_wdi_panel.csv
  Time:   ~2 minutes

STEP 4  Step4_Merge_Master_Panel.py
  Merges centrality (Step 2), vulnerability variables (Step 3),
  WDI GDP (Step 4b), USGS production, and MSP/alliance flags
  into one analysis-ready master panel.
  Output: data/04_master_panel.csv  (also REE_Master_Dataset.xlsx)

STEP 5  Step5_Regressions.py
  Exploratory OLS regressions (Python). Final regressions are in
  Stata (Step 10) with clustered standard errors.
  Output: data/05_regression_results.csv

STEP 6  Step6_Shock_Simulations.py
  Four counterfactual scenarios on the 2023 Layer 2 network:
    S1 — China export ban (removes all China L2 edges)
    S2 — Myanmar feedstock disruption (SF = 0.332)
    S3 — Combined S1 + S2
    S4 — MSP scale-up (doubles MSP member exports)
  Reports affected country counts and ΔSVI for each scenario.
  Output: data/06_shock_results.csv

STEP 7  Step7_CausalID.py
  Difference-in-differences event study around the February 2021
  Myanmar coup. Produces event study coefficients for Appendix Fig A.1.
  Output: data/07_event_study.csv

STEP 9  Step9_Stata_ntwrk.do  [Stata]
  Cross-platform centrality replication using stata-ntwrk v1.0.
  Replicates betweenness centrality and adds PageRank and reciprocity
  for Table A.4. Requires stata-ntwrk installed (see above).

STEP 10  Step10_Panel_Regressions_TWFE.do  [Stata]
  All main regressions: Models M1a–M1c (vulnerability) and
  M2a–M2d (bargaining power), plus sub-period stability (Table A.5).
  Two-way fixed effects (country + year), SEs clustered at country level.
  Exports Tables 2, 3, A.3, A.5 as in the paper.

STEP 10b  Step10b_Build_Broad_Panel.py
  Constructs broad HS code definitions for Table A.3 robustness checks.
  Output: data/broad_panel.csv

STEP 10c  Step10c_Save_Broad_DTA.py
  Converts broad_panel.csv to Stata .dta format for merge in Step 10.
  Output: data/broad_panel.dta

build_paper.py
  Generates all figures (Figures 1–7, Fig A.1) at 300 DPI from the
  processed data files. Run after all steps are complete.
  Output: figures/ directory

--------------------------------------------------------------------
DATA FILES INCLUDED
--------------------------------------------------------------------
REE_Master_Dataset.xlsx
  Analysis-ready master panel with all regression variables.
  Country-year observations, 2012–2024. Use this to skip Steps 1–4
  and go directly to Stata regressions (Step 10).

second_order_exposure_2023.csv
  Second-order indirect dependence values for all importing economies
  in 2023 (Table 3 in the paper). Columns: rank, country, iso3,
  direct_china_dependence, indirect_myanmar_exposure, feedstock_share.

--------------------------------------------------------------------
KEY VARIABLES (REE_Master_Dataset.xlsx)
--------------------------------------------------------------------
iso3                      Country ISO3 code
year                      2012–2024
china_import_share_L2     Share of Layer 2 imports sourced from China
betweenness_L2            Normalised betweenness centrality, Layer 2
betweenness_L1            Normalised betweenness centrality, Layer 1
dependent_importers_25pct Count of countries importing >25% from exporter i
dependent_importers_50pct Count of countries importing >50% from exporter i
supply_vulnerability_idx  Composite SVI (0–1)
supplier_hhi_L2           Herfindahl-Hirschman Index of import concentration
n_suppliers_L2            Number of active Layer 2 suppliers
alliance_diversity_idx    Count of MSP partners with >=5% supply share (post-2022)
msp_member                Binary: 1 if MSP member (post-2022)
export_restriction_binary Binary: 1 if country imposed REE export controls
log_gdp                   Log of GDP, current USD (World Development Indicators)

--------------------------------------------------------------------
CONTACT
--------------------------------------------------------------------
Sana Younas
University of Portsmouth
up2175371@myport.ac.uk

For questions about replication, please contact the corresponding author.
Raw data: BACI HS12 V202601 — cite as Gaulier & Zignago (2010),
CEPII Working Paper 2010-23. https://doi.org/10.2139/ssrn.1994500
