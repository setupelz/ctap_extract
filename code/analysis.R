
# LOAD NECESSARY PACKAGES ------------------------------------------------------

library(pacman)
p_load(here, readr, dplyr, purrr, ggplot2, tidyr, stringr, patchwork)

# LOAD DATA --------------------------------------------------------------------

# Read in all structured csv datasets in /output
ctaps <- list.files(here("output"), pattern = ".csv", full.names = TRUE) %>% 
  map_dfr(read_csv)

# Clean up
ctaps_cleaned <- ctaps %>%
  mutate(Country = str_extract(File, "^[^_]+"),
         Company = str_extract(File, "(?<=_)[^,]+"),
         Year = str_extract(File, "(?<=, )\\d{4}")) %>% 
  select(Country, Company, Year, Code, Text) %>% 
  arrange(Country, Company, Year) %>% 
  mutate(Scenario = as.numeric(grepl(Code, pattern = "Scenario")),
         IPCC = as.numeric(grepl(Code, pattern = "IPCC")),
         IEA = as.numeric(grepl(Code, pattern = "IEA")),
         Paris = as.numeric(grepl(Code, pattern = "Paris")),
         Offset = as.numeric(grepl(Code, pattern = "Offset")),
         Scope3 = as.numeric(grepl(Code, pattern = "Scope3")))

# Write to file
ctaps_cleaned %>% 
  write_csv(here("Manuscript", "Tables", "ctaps_cleaned.csv"))

# ANALYSIS ---------------------------------------------------------------------

ctaps_cleaned %>% 
  dplyr::count(Country, Company, Year) %>% 
  dplyr::count(Country, Company, Year) %>% 
  group_by(Country, Year) %>% 
  summarise(Companies = paste(Company, collapse = ", ")) %>% 
  write_csv(here("Manuscript", "Tables", "companies_per_year.csv"))

a <- ctaps_cleaned %>% 
  select(-Scope3) %>% 
  group_by(Country, Company, Year) %>% 
  summarise(across(Scenario:Offset, ~as.numeric(sum(.) > 0))) %>% 
  pivot_longer(cols = Scenario:Offset, names_to = "Code", values_to = "Count") %>% 
  group_by(Code) %>% 
  summarise(Share = sum(Count) / n()) %>%
  ggplot(aes(x = interaction(Code), y = Share)) +
  geom_col() +
  coord_flip() +
  theme_bw() +
  labs(y = "Share of reports mentioning", x = NULL) +
  scale_y_continuous(labels = scales::percent)

b <- ctaps_cleaned %>% 
  group_by(Country, Company, Year) %>% 
  summarise(across(Scenario:Offset, ~sum(.))) %>% 
  pivot_longer(cols = Scenario:Offset, names_to = "Code", values_to = "Count") %>% 
  ggplot(aes(x = interaction(Code), y = Count)) +
  geom_col() +
  coord_flip() +
  theme_bw() +
  labs(y = "Number of times mentioned", x = NULL)

wrap_plots(a,b)

