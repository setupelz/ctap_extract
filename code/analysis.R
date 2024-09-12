
# LOAD NECESSARY PACKAGES ------------------------------------------------------

library(pacman)
p_load(here, readr, readxl, dplyr, purrr, ggplot2, tidyr, stringr, patchwork,
       zoo, forcats, fastDummies, writexl, fuzzyjoin)

# LOAD DATA --------------------------------------------------------------------

# Read in all downloaded and processed PDFs
inputpdfs <- read_csv(here("data", "json", "processing_log.csv")) %>% 
  mutate(Company = str_extract(File, "^[^,]+"),
         Year = str_extract(File, "\\d{4}")) %>% 
  select(Country, Company, Year, Status)

# Read in all structured csv datasets in /output
ctaps <- list.files(here("output"), pattern = ".csv", full.names = TRUE) %>% 
  map_dfr(read_csv)

# Load in codes
codes <- read_csv(here("data", "codes.csv")) %>% 
  select(Codes = Code, Short)

# Load in Carbon Majors data (investor-owned firms)
carbon_majors <- read_csv(here("data", "carbonmajors_investorowned_2024.csv")) %>% 
  mutate(Ranking = str_extract(Ranking, "\\d+") %>% as.numeric())

# Load in Say on Climate Votes data
say_on_climate <- tibble(Company = c("Woodside Energy", "Santos", "AGL", "Glencore", "M&G", "Shell", "Centrica", 
                    "Barclays", "Mercialys", "Standard Chartered", "Rio Tinto", "UBS", 
                    "BHP", "Repsol", "Canadian Pacific Rail", "Nexity", 
                    "Carrefour", "BP", "TotalEnergies", "South23", 
                    "Canadian National Rail", 
                    "NatWest Group", "Anglo American", "Origin Energy", 
                    "Ferrovial", "Holcim Group", "Kingspan Group", "Aena SME", "ELIS", 
                    "Sasol", "Engie", "Getlink", "ATOS", "Equinor", "Amundi", 
                    "Ninety One", "Aviva", "Carmila", "Vinci", "National Grid", 
                    "London Stock Exchange Group", "SSE", "Moody's Corporation", 
                    "Atlantia (Mundys)", "Nestle", "Severn Trent", "S&P Global", "Unilever", 
                    "HSBC Holdings", "EDF", "Iberdrola", "Westpac", "Orica"),
                    SayOnClimate = "Yes")

# PREPARE ----------------------------------------------------------------------

# Clean up names and codes
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
  mutate(Year = ifelse(Year == "2032", "2023", Year), # fix one mislabelled year
         Company = case_when( # Fix mislabelled company names
           Company == "AngloAmerican" ~ "Anglo American",
           Company == "APA" ~ "APA Corporation",
           Company == "Antero Resources" ~ "Antero",
           Company == "bp" ~ "BP",
           Company == "Carmelia" ~ "Carmila",
           Company == "cemex" ~ "Cemex",
           Company == "conocophillips" ~ "ConocoPhillips",
           Company == "Cheasapeake" ~ "Chesapeake Energy",
           Company == "Consol Energy" ~ "CONSOL Energy",
           Company == "Canada Pacific Rail" ~ "Canadian Pacific Rail",
           Company == "EQT" ~ "EQT Corporation",
           Company == "pttep" ~ "PTTEP",
           Company == "PETRONAS" ~ "Petronas",
           Company == "Total Energies" ~ "TotalEnergies",
           Company == "exxaro" ~ "Exxaro Resources Ltd",
           Company == "Exxonmobil" ~ "ExxonMobil",
           Company == "Holcim" ~ "Holcim Group",
           Company == "INPEX" ~ "Inpex",
           Company == "SASOL" ~ "Sasol",
           Company == "seriti" ~ "Seriti",
           Company == "eni" ~ "Eni",
           Company == "ovintiv" ~ "Ovintiv",
           Company == "Woodside" ~ "Woodside Energy",
           TRUE ~ Company)) %>% 
  arrange(desc(Year), Country, Company) %>% 
  ungroup()

# Save the current year month day as yyyymmdd
date <- format(Sys.Date(), "%Y%m%d")

# Save newly processed files
ctaps_cleaned %>%
  select(c("Report", "ID", "Country", "Company", "Year", "Page", "Text", "Codes")) %>% 
  write_xlsx(here("output", paste0("ctaps_cleaned", date, ".xlsx")))

# PREPARE ANALYSIS SUBSET ------------------------------------------------------

# Define Carbon Majors that have held Say on Climate votes

# Carbon majors

# Subset priority companies meeting all three criteria
ctaps_cleaned_cm_latest <- ctaps_cleaned %>%
  arrange(Company, desc(Year)) %>% 
  dplyr::count(Company) %>% 
  transmute(Company = Company, ReportOrCTAP = "Yes") %>% 
  full_join(carbon_majors %>% select(Company, CarbonMajorRanking = Ranking)) %>% 
  full_join(say_on_climate) %>%
  ungroup() %>% 
  arrange(Company) %>% 
  na.omit() %>% 
  arrange(CarbonMajorRanking)

ctaps_cleaned %>% 
  arrange(Company) %>% 
  filter(Company %in% ctaps_cleaned_cm_latest$Company) %>%
  select(c("Report", "ID", "Country", "Company", "Year", "Page", "Text", "Codes")) %>% 
  write_xlsx(here("output", paste0("ctaps_cleaned_priority_", date, ".xlsx")))

