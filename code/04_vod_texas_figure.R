# 04_vod_texas_figure.R
# Analogue of Fig. 2 in Pierson et al. (2020): share of Texas state patrol
# stops of Black drivers in three 15-minute windows, by minutes since dusk.
# Like the paper, this uses all days of the year (not only the DST windows):
# the clock time is fixed within each panel, and the variation in darkness
# comes from sunset moving through the year.
#
# Input : data/raw/*_tx_statewide_*.rds
# Output: results/figures/vod_texas_fig2.png, results/tables/vod_texas_fig2.csv
#
# Run from the project root:  Rscript code/04_vod_texas_figure.R

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(ggplot2); library(maps)
})
# Reuse the sun-time and county helpers from 03_veil_of_darkness.R.
src <- readLines("code/03_veil_of_darkness.R")
eval(parse(text = src[grep("^sun_minutes <- ", src):(grep("^find_file <- ", src) - 1)]))
raw_dir <- "data/raw"
state_names <- c(TX = "texas"); state_tz <- c(TX = "America/Chicago")

f <- list.files(raw_dir, pattern = "_tx_statewide_.*\\.rds$", full.names = TRUE)[1]
d <- readRDS(f)
d <- d[, c("date", "time", "subject_race", "county_name", "type")]
d <- d %>%
  filter(type == "vehicular", !is.na(time), !is.na(county_name),
         date >= as.Date("2011-01-01"), subject_race %in% c("white", "black")) %>%
  transmute(date, minute = as.numeric(time) / 60, is_black = subject_race == "black",
            county = norm_county(county_name))
# Keep the three clock-time windows first (cheap), then add sun times.
d <- filter(d, minute >= 19 * 60, minute < 19 * 60 + 45)
top <- d %>% count(county, sort = TRUE) %>% slice_head(n = 20)
d <- semi_join(d, top, by = "county") %>% inner_join(county_centroids("TX"), by = "county")
sun <- d %>% distinct(date, county, center_lat, center_lng) %>%
  mutate(sunset_minute = sun_minutes(date, center_lat, center_lng, "America/Chicago", 90.833),
         dusk_minute   = sun_minutes(date, center_lat, center_lng, "America/Chicago", 96))
d <- left_join(d, sun, by = c("date", "county", "center_lat", "center_lng")) %>%
  filter(!(minute >= sunset_minute & minute <= dusk_minute)) %>%
  mutate(window = cut(minute, c(19 * 60, 19 * 60 + 15, 19 * 60 + 30, 19 * 60 + 45),
                      labels = c("7:00-7:15 pm", "7:15-7:30 pm", "7:30-7:45 pm"), right = FALSE),
         min_since_dusk = round((minute - dusk_minute) / 10) * 10,
         is_dark = minute >= dusk_minute)

fig <- d %>% group_by(window, min_since_dusk, is_dark) %>%
  summarize(share_black = mean(is_black), n = n(), .groups = "drop") %>%
  filter(n >= 200)
write_csv(fig, "results/tables/vod_texas_fig2.csv")

p <- ggplot(fig, aes(min_since_dusk, share_black)) +
  geom_point(aes(size = n), alpha = 0.55) +
  geom_smooth(aes(weight = n, group = is_dark), method = "lm", formula = y ~ x,
              se = FALSE, colour = "grey25", linewidth = 0.7) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  facet_wrap(~ window) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_size_area(max_size = 4, guide = "none") +
  labs(x = "Minutes since dusk", y = "Share of stopped drivers who are Black",
       caption = "Texas state patrol, 2011-2017, top 20 counties. Sunset-to-dusk stops removed.") +
  theme_minimal(base_size = 11)
ggsave("results/figures/vod_texas_fig2.png", p, width = 9, height = 3.5, dpi = 200)

cat("Share Black, light vs dark, by window:\n")
print(d %>% group_by(window, is_dark) %>% summarize(share_black = mean(is_black), n = n(), .groups = "drop"))
