# 01_build_did_data.R
# Builds the state x date x race panel for the marijuana-legalization DiD in
# Pierson et al. (2020), following the authors' pipeline in
# lib/eligibility.R in github.com/stanford-policylab/opp (load_base_for, load_mj_for,
# add_mj_calculated_features).
#
# Input : data/raw/*_<st>_statewide_*.rds  (Stanford Open Policing Project)
# Output: data/derived/mj_panel.csv  (one row per state, date, race)
#         results/tables/mj_sample_log.csv  (rows kept at each step)
#
# Run from the project root:  Rscript code/01_build_did_data.R

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
})

raw_dir     <- "data/raw"
derived_dir <- "data/derived"
dir.create(derived_dir, showWarnings = FALSE, recursive = TRUE)
dir.create("results/tables", showWarnings = FALSE, recursive = TRUE)

treated  <- c("CO", "WA")
controls <- c("AZ", "CA", "FL", "MA", "MT", "NC", "OH", "RI", "SC", "TX", "VT", "WI")
states   <- c(treated, controls)

find_file <- function(st) {
  f <- list.files(raw_dir, pattern = sprintf("_%s_statewide_.*\\.rds$", tolower(st)),
                  full.names = TRUE)
  if (length(f) == 0) stop("No statewide RDS file found for ", st)
  f[1]
}

# Share of non-missing values of x, by month; months below `threshold` are dropped.
drop_low_coverage_months <- function(d, x, threshold = 0.5) {
  cov <- d %>%
    mutate(month = format(date, "%Y-%m")) %>%
    group_by(month) %>%
    summarize(coverage = mean(!is.na(.data[[x]])), .groups = "drop") %>%
    filter(coverage >= threshold)
  d %>% mutate(month = format(date, "%Y-%m")) %>%
    semi_join(cov, by = "month") %>%
    select(-month)
}

log_rows <- list()
panels   <- list()

for (st in states) {
  message("Processing ", st)
  d <- readRDS(find_file(st))
  n0 <- nrow(d)
  # Keep only the columns we need, to save memory on the large states (CA, TX).
  d <- d[, intersect(names(d), c("date", "type", "subject_race", "search_conducted",
                                 "search_basis", "department_name"))]
  gc()

  # North Carolina's file covers several agencies; the authors keep the state highway patrol only.
  if (st == "NC" && "department_name" %in% names(d))
    d <- filter(d, department_name == "NC State Highway Patrol")

  # Vehicular stops only, 2011-2015 (the authors truncate the DiD after 2015).
  if ("type" %in% names(d)) d <- filter(d, type == "vehicular")
  d <- filter(d, !is.na(date), date >= as.Date("2011-01-01"), date <= as.Date("2015-12-31"))

  # Months with fewer than 50 stops are dropped.
  keep_m <- d %>% count(m = format(date, "%Y-%m")) %>% filter(n >= 50) %>% pull(m)
  d <- filter(d, format(date, "%Y-%m") %in% keep_m)

  # Race must be recorded in at least half the stops each month ("unknown" counts as missing).
  d <- d %>% mutate(subject_race = as.character(subject_race),
                    subject_race = if_else(subject_race == "unknown", NA_character_, subject_race))
  d <- drop_low_coverage_months(d, "subject_race", 0.5)
  d <- filter(d, subject_race %in% c("white", "black", "hispanic"))

  # Search data must be recorded in at least half the stops each month.
  if (!"search_conducted" %in% names(d)) { message("  no search data, skipped"); next }
  d <- drop_low_coverage_months(d, "search_conducted", 0.5)
  d <- filter(d, !is.na(search_conducted))

  # Need data both before and after 2012.
  yrs <- range(as.integer(format(d$date, "%Y")))
  if (yrs[1] > 2012 || yrs[2] < 2012) { message("  no pre/post data, skipped"); next }

  if (!"search_basis" %in% names(d)) d$search_basis <- NA_character_

  leg_date <- if (st == "CO") as.Date("2012-12-10") else as.Date("2012-12-09")

  panel <- d %>%
    mutate(
      search_basis = as.character(search_basis),
      # Discretionary search: basis missing, or k9 / plain view / probable cause / consent.
      is_discretionary_search = search_conducted &
        (is.na(search_basis) |
           search_basis %in% c("k9", "plain view", "probable cause", "consent"))
    ) %>%
    group_by(date, subject_race) %>%
    summarize(n_stops = n(),
              n_searches = sum(is_discretionary_search),
              .groups = "drop") %>%
    mutate(state = st,
           legalization_date = leg_date,
           is_treatment_state = st %in% treated,
           is_post = date >= leg_date,
           is_treatment = is_treatment_state & is_post,
           years_since_legalization = as.numeric(date - leg_date) / 365)

  panels[[st]] <- panel
  log_rows[[st]] <- tibble(state = st, rows_raw = n0, stops_used = sum(panel$n_stops),
                           first_date = min(panel$date), last_date = max(panel$date))
  rm(d); gc()
}

mj <- bind_rows(panels)
write_csv(mj, file.path(derived_dir, "mj_panel.csv"))
write_csv(bind_rows(log_rows), "results/tables/mj_sample_log.csv")
message("Done: ", nrow(mj), " state-date-race cells, ", sum(mj$n_stops), " stops")
