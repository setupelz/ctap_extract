
# LOAD NECESSARY PACKAGES ------------------------------------------------------

library(pacman)
p_load(here, readr, readxl, dplyr, purrr, ggplot2, tidyr, stringr, patchwork,
       zoo, forcats, fastDummies, writexl)

# LOAD DATA --------------------------------------------------------------------

# Read in all structured csv datasets in /output
ctaps <- list.files(here("output"), pattern = ".csv", full.names = TRUE) %>% 
  map_dfr(read_csv)

# Load in codes
codes <- read_csv(here("data", "codes.csv")) %>% 
  select(Codes = Code, Short)

# Read already processed CTAPS (all files saved as .xlsx)
already_processed <- list.files(here("output"), pattern = ".xlsx", full.names = TRUE) %>% 
  map_dfr(read_xlsx)

# ANALYSIS ---------------------------------------------------------------------

ctaps_cleaned <- ctaps %>% 
  mutate(Codes = str_replace(Codes, "\\[", ""),
         Codes = str_replace(Codes, "\\]", "")) %>%
  separate_rows(Codes, sep = ", ") %>% 
  left_join(codes) %>% 
  mutate(File = str_replace(File, "_", ", "),
         File = str_replace(File, "2024 ", "2024, ")) %>% 
  separate_wider_delim(File, delim = ", ", names = c("Country", "Company", "Year", "Report"), too_many = "drop") %>% 
  select(-Codes) %>% 
  group_by(Country, Company, Year, Report, Page, ID, Text) %>% 
  summarise(Codes = paste(Short, collapse = ", ")) %>% 
  mutate(Year = ifelse(Year == "2032", "2023", Year)) %>% 
  arrange(desc(Year), Country, Company)

# Save the current year month day as yyyymmdd
date <- format(Sys.Date(), "%Y%m%d")

# Save newly processed files
ctaps_cleaned %>%
  # anti_join(already_processed) %>% 
  select(c("Report", "ID", "Country", "Company", "Year", "Page", "Text", "Codes")) %>% 
  write_xlsx(here("output", paste0("ctaps_cleaned", date, ".xlsx")))

