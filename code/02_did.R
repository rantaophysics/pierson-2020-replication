# 02_did.R
# Replicates the marijuana-legalization DiD (Table 1, Figs 4-5) of
# Pierson et al. (2020) and runs our robustness checks.
#
# Input : data/derived/mj_panel.csv  (from 01_build_did_data.R)
# Output: results/tables/did_table1_replication.csv
#         results/tables/did_robustness.csv
#         results/tables/did_placebo_inference.csv
#         results/figures/did_search_rates_treated.png
#         results/figures/did_search_rates_controls.png
#         results/figures/did_event_study.png
#
# Run from the project root:  Rscript code/02_did.R

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(ggplot2)
  library(broom)
  library(sandwich)
  library(lmtest)
})

dir.create("results/tables",  showWarnings = FALSE, recursive = TRUE)
dir.create("results/figures", showWarnings = FALSE, recursive = TRUE)

mj <- read_csv("data/derived/mj_panel.csv", show_col_types = FALSE) %>%
  mutate(subject_race = factor(subject_race, levels = c("white", "black", "hispanic")),
         state = factor(state))

race_cols <- c(white = "#2C5BB7", black = "black", hispanic = "#C8332B")

# ---------------------------------------------------------------------------
# 1. Paper's specification (Table 1): logit on counts
#    logit P(search) = state FE + linear trend + race FE + race-specific treatment
# ---------------------------------------------------------------------------
m_paper <- glm(
  cbind(n_searches, n_stops - n_searches) ~
    state + years_since_legalization + subject_race + is_treatment:subject_race,
  family = binomial, data = mj
)

table1 <- tidy(m_paper) %>%
  filter(!grepl("^state", term)) %>%
  mutate(odds_ratio = exp(estimate))
write_csv(table1, "results/tables/did_table1_replication.csv")
print(table1)

# ---------------------------------------------------------------------------
# 2. Robustness
#   (a) same model, standard errors clustered by state (14 clusters, 2 treated)
#   (b) quarter fixed effects instead of a single linear trend
#   (c) linear probability model on the search rate, weighted by stops
# ---------------------------------------------------------------------------
treat_terms <- function(m) grepl("is_treatment", names(coef(m)))

vc_state <- vcovCL(m_paper, cluster = ~ state)
rob_a <- coeftest(m_paper, vcov. = vc_state)[treat_terms(m_paper), , drop = FALSE]

mj <- mj %>% mutate(quarter = paste0(format(date, "%Y"), "Q", (as.integer(format(date, "%m")) - 1) %/% 3 + 1))
m_qfe <- glm(
  cbind(n_searches, n_stops - n_searches) ~
    state + factor(quarter) + subject_race + is_treatment:subject_race,
  family = binomial, data = mj
)
rob_b <- coeftest(m_qfe, vcov. = vcovCL(m_qfe, cluster = ~ state))[treat_terms(m_qfe), , drop = FALSE]

mj <- mj %>% mutate(search_rate = n_searches / n_stops)
m_lpm <- lm(search_rate ~ state + factor(quarter) + subject_race + is_treatment:subject_race,
            data = mj, weights = n_stops)
rob_c <- coeftest(m_lpm, vcov. = vcovCL(m_lpm, cluster = ~ state))[treat_terms(m_lpm), , drop = FALSE]

to_tbl <- function(ct, spec) {
  tibble(spec = spec, term = rownames(ct), estimate = ct[, 1], std_error = ct[, 2],
         p_value = ct[, 4])
}
robust <- bind_rows(
  tidy(m_paper) %>% filter(grepl("is_treatment", term)) %>%
    transmute(spec = "Paper: logit, linear trend, iid SE", term, estimate,
              std_error = std.error, p_value = p.value),
  to_tbl(rob_a, "Logit, linear trend, SE clustered by state"),
  to_tbl(rob_b, "Logit, quarter FE, SE clustered by state"),
  to_tbl(rob_c, "Linear probability model, quarter FE, SE clustered by state")
)
write_csv(robust, "results/tables/did_robustness.csv")
print(robust)

# ---------------------------------------------------------------------------
# 3. Placebo (randomization) inference: assign "legalization" to every pair of
#    control states, re-estimate, and compare with the real estimate.
# ---------------------------------------------------------------------------
ctrl <- c("AZ", "CA", "FL", "MA", "MT", "NC", "OH", "RI", "SC", "TX", "VT", "WI")
ctrl <- intersect(ctrl, levels(mj$state))
mj_c <- mj %>% filter(state %in% ctrl) %>% droplevels()
pairs <- combn(ctrl, 2, simplify = FALSE)

placebo <- lapply(pairs, function(pr) {
  dd <- mj_c %>% mutate(is_treatment = state %in% pr & is_post)
  m <- glm(cbind(n_searches, n_stops - n_searches) ~
             state + years_since_legalization + subject_race + is_treatment:subject_race,
           family = binomial, data = dd)
  tidy(m) %>% filter(grepl("is_treatment", term)) %>%
    transmute(pair = paste(pr, collapse = "+"), term, estimate)
}) %>% bind_rows()

actual <- table1 %>% filter(grepl("is_treatment", term)) %>% select(term, actual = estimate)
placebo_summary <- placebo %>%
  left_join(actual, by = "term") %>%
  group_by(term) %>%
  summarize(actual = first(actual),
            n_placebos = n(),
            share_placebos_as_negative = mean(estimate <= actual),
            placebo_min = min(estimate), placebo_median = median(estimate),
            .groups = "drop")
write_csv(placebo, "results/tables/did_placebo_estimates.csv")
write_csv(placebo_summary, "results/tables/did_placebo_inference.csv")
print(placebo_summary)

# ---------------------------------------------------------------------------
# 4. Figures: quarterly search rates (Figs 4-5) and an event study
# ---------------------------------------------------------------------------
quarterly <- mj %>%
  group_by(state, subject_race, quarter) %>%
  summarize(rate = 100 * sum(n_searches) / sum(n_stops),
            qdate = min(date), .groups = "drop") %>%
  filter(quarter != "2012Q4")   # legalization quarter mixes pre and post

plot_rates <- function(dat, ncol) {
  ggplot(dat, aes(qdate, rate, colour = subject_race)) +
    geom_line() +
    geom_vline(xintercept = as.Date("2012-12-09"), linetype = "dashed") +
    facet_wrap(~ state, scales = "free_y", ncol = ncol) +
    scale_colour_manual(values = race_cols, name = NULL) +
    labs(x = NULL, y = "Search rate (%)") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")
}
ggsave("results/figures/did_search_rates_treated.png",
       plot_rates(filter(quarterly, state %in% c("CO", "WA")), 2), width = 8, height = 3.5, dpi = 200)
ggsave("results/figures/did_search_rates_controls.png",
       plot_rates(filter(quarterly, !state %in% c("CO", "WA")), 4), width = 10, height = 6, dpi = 200)

# Event study (linear probability, quarters relative to 2012Q4, omitted = -1)
qidx <- function(q) as.integer(substr(q, 1, 4)) * 4 + as.integer(substr(q, 6, 6))
mj <- mj %>% mutate(rel_q = qidx(quarter) - qidx("2012Q4"),
                    treat_state = state %in% c("CO", "WA"))
es <- lm(search_rate ~ state + factor(quarter) + subject_race +
           relevel(factor(ifelse(treat_state, rel_q, -1)), ref = "-1"),
         data = mj, weights = n_stops)
es_ct <- coeftest(es, vcov. = vcovCL(es, cluster = ~ state))
es_tbl <- tibble(term = rownames(es_ct), estimate = es_ct[, 1], se = es_ct[, 2]) %>%
  filter(grepl("relevel", term)) %>%
  mutate(rel_q = as.integer(sub(".*\"-1\"\\)", "", term))) %>%
  bind_rows(tibble(rel_q = -1L, estimate = 0, se = 0))
write_csv(es_tbl, "results/tables/did_event_study.csv")

p_es <- ggplot(es_tbl, aes(rel_q, 100 * estimate)) +
  geom_hline(yintercept = 0, colour = "grey50") +
  geom_vline(xintercept = -0.5, linetype = "dashed") +
  geom_pointrange(aes(ymin = 100 * (estimate - 1.96 * se), ymax = 100 * (estimate + 1.96 * se))) +
  labs(x = "Quarters relative to legalization (2012Q4)",
       y = "Effect on search rate (pp)",
       caption = "LPM with state, quarter and race FE; SE clustered by state (14 clusters, 2 treated).") +
  theme_minimal(base_size = 11)
ggsave("results/figures/did_event_study.png", p_es, width = 8, height = 4, dpi = 200)

message("DiD replication done.")
