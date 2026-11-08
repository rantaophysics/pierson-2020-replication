# Replication of Pierson et al. (2020): racial disparities in police stops

A replication of

> Pierson, E., Simoiu, C., Overgoor, J. et al. A large-scale analysis of racial disparities in police stops across the United States. *Nature Human Behaviour* 4, 736–745 (2020). https://doi.org/10.1038/s41562-020-0858-1

done for STAT 5200 (econometrics), Fall 2026, and presented in class on November 11, 2026. It uses the authors' public data from the [Stanford Open Policing Project](https://openpolicing.stanford.edu) and follows their code at [stanford-policylab/opp](https://github.com/stanford-policylab/opp).

## Results

**Difference-in-differences (Table 1).** The effect of recreational marijuana legalization in Colorado and Washington on the log odds of a search, using the same 14 states and specification as the paper:

| Drivers | Paper | Ours | Ours, SE clustered by state |
|---|---|---|---|
| White | −0.96 (0.02) | −1.00 (0.02) | −1.00 (0.07) |
| Black | −0.98 (0.06) | −0.98 (0.06) | −0.98 (0.30) |
| Hispanic | −0.69 (0.03) | −0.79 (0.03) | −0.79 (0.21) |

- **Placebo test:** none of the 66 pairs of control states, treated as if they legalized in December 2012, gives an effect as negative as the real one (p ≈ 0.015).
- **Event study:** estimates before legalization are near zero; afterwards the search rate is about 0.2 to 0.35 percentage points lower.
- **Scale:** in a linear probability model the effect for white drivers is only −0.08 percentage points and not significant, because their base search rate was about 0.3%.

**Veil of darkness (state patrols).** The darkness coefficient is −0.053 (95% CI −0.081 to −0.026), against the paper's −0.033 (−0.039 to −0.027). Only Texas, Florida, Ohio and Washington among our 14 states record stop times well enough; the paper pools 21 state patrols.

**Not replicated:** the threshold test for search decisions (a Bayesian model fitted in Stan) and the veil-of-darkness test for city police departments.

## Repository layout

| Path | Contents |
|---|---|
| `code/` | Analysis scripts, run in order from the repository root |
| `data/download_data.sh` | Downloads the 14 statewide files (about 2.2 GB) into `data/raw/` |
| `data/derived/mj_panel.csv` | State × day × race panel used in the DiD |
| `results/tables/` | CSV outputs; `replication_vs_paper.csv` is the side-by-side comparison |
| `results/figures/` | Figures from the R scripts |
| `results/figures/slides/` | Figures used in the presentation (PDF, SVG, PNG) |
| `notes/methods_notes.pdf` | Technical notes on the veil of darkness, outcome and threshold tests, DiD and inference |
| `slides/` | The 10-minute presentation (PowerPoint) |

## Reproducing the results

```bash
bash data/download_data.sh            # raw data, about 2.2 GB
Rscript code/01_build_did_data.R      # builds data/derived/mj_panel.csv
Rscript code/02_did.R                 # Table 1, robustness, placebo test, event study
Rscript code/03_veil_of_darkness.R    # veil-of-darkness model in DST windows
Rscript code/04_vod_texas_figure.R    # Texas figure (analogue of the paper's Fig. 2)
python3 code/05_slide_figures.py      # presentation figures
```

`02_did.R` runs on the included `mj_panel.csv`, so the DiD results can be checked without downloading the raw data.

Requirements: R with `dplyr`, `readr`, `tidyr`, `ggplot2`, `broom`, `sandwich`, `lmtest` and `maps`; Python 3 with `numpy`, `pandas` and `matplotlib`. Loading the California and Texas files needs about 8 GB of memory.

## Differences from the paper

- **DiD:** the small differences in coefficients likely come from the data release (California and Montana are from the 2023 update) and from filters we simplified, such as the removal of anomalous sub-geographies.
- **Veil of darkness:** state patrols only, on four states. Sunset and dusk times are computed with the NOAA solar algorithm at county centroids from the R `maps` package.
- **Search decisions:** the presentation shows the paper's search rates, hit rates and thresholds; we did not re-estimate them.
