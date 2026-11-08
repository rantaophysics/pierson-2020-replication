# 03_veil_of_darkness.R
# Veil-of-darkness test around daylight saving time (DST) changes, following
# Pierson et al. (2020) and the authors' code (veil_of_darkness.R,
# eligibility.R: load_dst_vod_for). We run it on state patrol data only.
#
# Model (on counts, as in the authors' train_dst_model):
#   cbind(n_black, n_white) ~ is_dark + ns(minute, df = 6) + county + season*year
#
# Input : data/raw/*_<st>_statewide_*.rds
# Output: results/tables/vod_coefficients.csv   (pooled and by state, spline df 1-6)
#         results/tables/vod_sample_log.csv
#         (the Texas figure is made by 04_vod_texas_figure.R)
#
# Run from the project root:  Rscript code/03_veil_of_darkness.R

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(splines)
  library(broom)
  library(maps)
})

raw_dir <- "data/raw"
dir.create("results/tables",  showWarnings = FALSE, recursive = TRUE)
dir.create("results/figures", showWarnings = FALSE, recursive = TRUE)

# State patrols we use (AZ is excluded because it does not observe DST).
vod_states <- c("TX", "WA", "NC", "FL", "SC", "OH", "MT", "WI", "VT", "CO", "MA", "RI", "CA")
state_names <- c(TX = "texas", WA = "washington", NC = "north carolina", FL = "florida",
                 SC = "south carolina", OH = "ohio", MT = "montana", WI = "wisconsin",
                 VT = "vermont", CO = "colorado", MA = "massachusetts", RI = "rhode island",
                 CA = "california")
state_tz <- c(TX = "America/Chicago", WA = "America/Los_Angeles", NC = "America/New_York",
              FL = "America/New_York", SC = "America/New_York", OH = "America/New_York",
              MT = "America/Denver", WI = "America/Chicago", VT = "America/New_York",
              CO = "America/Denver", MA = "America/New_York", RI = "America/New_York",
              CA = "America/Los_Angeles")

# ---------------------------------------------------------------------------
# Sun times (NOAA algorithm). Returns local clock minutes after midnight for
# sunset (zenith 90.833) and dusk = end of civil twilight (zenith 96).
# ---------------------------------------------------------------------------
sun_minutes <- function(date, lat, lng, tz, zenith) {
  doy  <- as.integer(format(date, "%j"))
  gam  <- 2 * pi / 365 * (doy - 1)
  eqt  <- 229.18 * (0.000075 + 0.001868 * cos(gam) - 0.032077 * sin(gam) -
                      0.014615 * cos(2 * gam) - 0.040849 * sin(2 * gam))
  decl <- 0.006918 - 0.399912 * cos(gam) + 0.070257 * sin(gam) - 0.006758 * cos(2 * gam) +
    0.000907 * sin(2 * gam) - 0.002697 * cos(3 * gam) + 0.00148 * sin(3 * gam)
  latr <- lat * pi / 180
  ha   <- acos(pmin(1, pmax(-1, cos(zenith * pi / 180) / (cos(latr) * cos(decl)) -
                                tan(latr) * tan(decl))))
  utc_min <- 720 - 4 * (lng - ha * 180 / pi) - eqt          # setting: + hour angle
  utc <- as.POSIXct(format(date), tz = "UTC") + utc_min * 60
  loc <- as.POSIXlt(utc, tz = tz)
  loc$hour * 60 + loc$min + loc$sec / 60
}

# County centroids from the maps package (mean of the polygon vertices).
county_centroids <- function(st) {
  m <- map("county", state_names[[st]], plot = FALSE, fill = TRUE)
  out <- lapply(seq_along(m$names), function(i) NULL)
  brk <- c(0, which(is.na(m$x)), length(m$x) + 1)
  tibble(id = rep(seq_len(length(brk) - 1), diff(brk) - 1),
         x = m$x[!is.na(m$x)], y = m$y[!is.na(m$y)]) %>%
    mutate(name = m$names[id]) %>%
    group_by(name) %>%
    summarize(center_lng = mean(x), center_lat = mean(y), .groups = "drop") %>%
    mutate(county = sub(":.*", "", sub("^[^,]+,", "", name))) %>%
    group_by(county) %>%
    summarize(center_lng = mean(center_lng), center_lat = mean(center_lat), .groups = "drop")
}
norm_county <- function(x) {
  x <- tolower(x)
  x <- sub(" county$| parish$", "", x)
  x <- gsub("\\.", "", x)
  x <- gsub("^saint ", "st ", x)
  trimws(x)
}

# DST start (2nd Sunday of March) and end (1st Sunday of November), 2007 rules.
nth_sunday <- function(year, month, n) {
  d <- as.Date(sprintf("%d-%02d-01", year, month))
  first <- d + ((7 - as.integer(format(d, "%u"))) %% 7)
  first + 7 * (n - 1)
}

find_file <- function(st) {
  f <- list.files(raw_dir, pattern = sprintf("_%s_statewide_.*\\.rds$", tolower(st)),
                  full.names = TRUE)
  if (length(f) == 0) NA_character_ else f[1]
}

pieces <- list()
log_rows <- list()

for (st in vod_states) {
  f <- find_file(st)
  if (is.na(f)) { message(st, ": file missing, skipped"); next }
  message("Processing ", st)
  d <- readRDS(f)
  need <- c("date", "time", "subject_race", "county_name")
  if (!all(need %in% names(d))) { message("  missing time or county, skipped"); next }
  if (st == "NC" && "department_name" %in% names(d))
    d <- filter(d, department_name == "NC State Highway Patrol")
  if ("type" %in% names(d)) d <- filter(d, type == "vehicular")

  d <- d %>%
    filter(!is.na(date), !is.na(time), !is.na(county_name),
           date >= as.Date("2011-01-01"), date <= as.Date("2018-12-31"),
           subject_race %in% c("white", "black")) %>%
    transmute(date, minute = as.numeric(time) / 60,
              is_black = subject_race == "black",
              county = norm_county(county_name))
  if (nrow(d) == 0 || mean(d$minute == 0) > 0.2) { message("  no usable times, skipped"); next }

  # Stops within 30 days of a DST change.
  yrs <- tibble(year = 2011:2018,
                dst_start = nth_sunday(2011:2018, 3, 2),
                dst_end   = nth_sunday(2011:2018, 11, 1))
  d <- d %>%
    mutate(year = as.integer(format(date, "%Y"))) %>%
    left_join(yrs, by = "year") %>%
    mutate(spring = abs(as.numeric(date - dst_start)) <= 30,
           fall   = abs(as.numeric(date - dst_end))   <= 30) %>%
    filter(spring | fall) %>%
    mutate(season = if_else(spring, "spring", "fall"))

  # Sunset and dusk at the county centroid.
  cc <- county_centroids(st)
  d <- inner_join(d, cc, by = "county")
  sun <- d %>% distinct(date, county, center_lat, center_lng) %>%
    mutate(sunset_minute = sun_minutes(date, center_lat, center_lng, state_tz[[st]], 90.833),
           dusk_minute   = sun_minutes(date, center_lat, center_lng, state_tz[[st]], 96))
  d <- left_join(d, sun, by = c("date", "county", "center_lat", "center_lng"))

  # Inter-twilight window; drop the sunset-to-dusk period.
  n_window <- nrow(d)
  d <- d %>%
    filter(minute >= min(dusk_minute), minute <= max(dusk_minute)) %>%
    filter(!(minute >= sunset_minute & minute <= dusk_minute))

  # County-years with at least 100 stops per race; top 20 counties by stops.
  ok <- d %>% group_by(county, year) %>%
    summarize(nb = sum(is_black), nw = sum(!is_black), .groups = "drop") %>%
    filter(nb >= 100, nw >= 100)
  d <- semi_join(d, ok, by = c("county", "year"))
  top <- d %>% count(county, sort = TRUE) %>% slice_head(n = 20)
  d <- semi_join(d, top, by = "county")
  if (nrow(d) == 0) { message("  nothing left after filters"); next }

  d <- d %>% mutate(state = st,
                    is_dark = minute >= dusk_minute,
                    rounded_minute = round(minute / 5) * 5)
  pieces[[st]] <- d
  log_rows[[st]] <- tibble(state = st, stops_in_dst_windows = n_window,
                           stops_used = nrow(d), counties = n_distinct(d$county),
                           share_black = mean(d$is_black), share_dark = mean(d$is_dark))
  rm(d); gc()
}

vod <- bind_rows(pieces) %>% mutate(geography = paste(county, state, sep = ", "))
write_csv(bind_rows(log_rows), "results/tables/vod_sample_log.csv")

fit_vod <- function(dat, df) {
  agg <- dat %>%
    group_by(is_dark, rounded_minute, geography, season, year) %>%
    summarize(n_black = sum(is_black), n_white = sum(!is_black), .groups = "drop") %>%
    mutate(year = factor(year))
  m <- glm(cbind(n_black, n_white) ~ is_dark + ns(rounded_minute, df = df) +
             geography + season * year,
           family = binomial, data = agg)
  tidy(m) %>% filter(term == "is_darkTRUE") %>%
    transmute(estimate, std_error = std.error, p_value = p.value)
}

coefs <- bind_rows(
  lapply(1:6, function(k) fit_vod(vod, k) %>% mutate(sample = "Pooled state patrols", spline_df = k)),
  lapply(unique(vod$state), function(s)
    fit_vod(filter(vod, state == s), 6) %>% mutate(sample = s, spline_df = 6))
) %>% select(sample, spline_df, everything()) %>%
  mutate(odds_ratio = exp(estimate), ci_low = estimate - 1.96 * std_error,
         ci_high = estimate + 1.96 * std_error)
write_csv(coefs, "results/tables/vod_coefficients.csv")
print(coefs, n = 50)

message("Veil of darkness done.")
