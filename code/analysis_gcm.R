
# LOAD NECESSARY PACKAGES -------------------------------------------------

library(pacman)

p_load(dplyr, tidyr, readr, ggplot2, here)

# LOAD DATA ---------------------------------------------------------------

gcm_data <- read_csv(here("Data", "secondarydata", "emissions_high_granularity.csv"))
ctap_data <- read_csv(here("Manuscript", "Tables", "companies_per_year.csv"))

# DATA SUMMARY ------------------------------------------------------------

gcm_data %>% 
  select(year, parent_entity, parent_type, commodity, ends_with("MtCO2")) %>% 
  mutate(commodity_cat = case_when(
    grepl(commodity, pattern = "Coal") ~ "Coal",
    TRUE ~ commodity)) %>% 
  group_by(year, parent_type, commodity_cat) %>%
  summarise(across(ends_with("MtCO2"), ~sum(as.numeric(.)))) %>% 
  pivot_longer(cols = ends_with("MtCO2"), names_to = "emission_type", values_to = "emissions") %>% 
  filter(year >= 1990) %>% 
  ggplot(aes(x = year, y = emissions / 1e3, fill = parent_type)) +
  geom_col(position = "stack", size = 1) +
  scale_x_continuous(breaks = scales::pretty_breaks(n = 10)) +
  labs(
    x = "Year",
    y = "Emissions (GtCO2)",
    fill = NULL
  ) +
  theme_bw() +
  theme(
    text = element_text(size = 12),
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "bottom",
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank()
  ) +
  scale_fill_brewer(palette = "Set2")

# AUSTRALIA --------------------------------------------------------------------

ctap_aus <- ctap_data %>% 
  filter(Country == "Australia") %>% 
  separate_longer_delim(Companies, delim = ", ")

gcm_aus <- gcm_data %>% 
  filter(grepl(parent_entity, pattern = paste(unique(ctap_aus$Companies), collapse = "|")) |
           grepl(reporting_entity, pattern = "BHP|Santos|Woodside|Whitehaven")) 

unique(ctap_aus$Companies)
unique(gcm_aus$parent_entity)

            