
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
  summarise(Codes = paste(Short, collapse = ", "))

ctaps_cleaned %>%
  write_xlsx(here("output", "ctaps_cleaned.xlsx"))

ctaps_cleaned %>%
  ungroup() %>% 
  dplyr::count(Country, Company, Year) %>%
  dplyr::count(Country, Company, Year) %>%
  group_by(Year) %>% 
  summarise(Companies = paste(Company, collapse = ", ")) %>%
  write_csv(here("Manuscript", "Tables", "companies_per_year.csv"))

a <- ctaps_cleaned %>%
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

# VISUALISE SPECIFIC PATTERNS --------------------------------------------------

# Historical GHGs
histghg <- read_csv(here("data", "secondarydata", "total-ghg-emissions.csv")) %>%
  filter(Entity == "World") %>%
  transmute(Year = Year, GCP_GtCO2e = `Annual greenhouse gas emissions in CO₂ equivalents` / 1e9)

# AR6
ar6 <- read_csv(here::here("data", "secondarydata", "1668008312256-AR6_Scenarios_Database_World_v1.1.csv.zip"))
metadata <- read_xlsx(here::here("data", "secondarydata", "AR6_Scenarios_Database_metadata_indicators_v1.1.xlsx"),
                      sheet = 2)
ar6vars <- ar6 %>% distinct(Variable)

# AR6 IMPs World
ar6imps <- tibble::tribble(
  ~Scenario,                  ~Model, ~Name,
  "EN_NPi2020_400f_lowBECCS",            "COFFEE 1.1", "Neg",
  "DeepElec_SSP2_ HighRE_Budg900", "REMIND-MAgPIE 2.1-4.3", "Ren",
  "LowEnergyDemand_1.3_IPCC", "MESSAGEix-GLOBIOM 1.0",  "LD",
  "CO_Bridge",             "WITCH 5.0",  "GS",
  "SusDev_SDP-PkBudg1000", "REMIND-MAgPIE 2.1-4.2",  "SP"
  ) %>%
  left_join(ar6) %>%
  filter(Variable %in% c(
    "Emissions|Kyoto Gases",
    "AR6 climate diagnostics|Surface Temperature (GSAT)|MAGICCv7.5.3|50.0th Percentile")) %>%
  pivot_longer(cols = matches("\\d{4}"), names_to = "Year") %>%
  select(-Unit) %>%
  pivot_wider(names_from = Variable, values_from = value) %>%
  mutate(ar6IMP_GtCO2e = `Emissions|Kyoto Gases` / 1e3,
         ar650pc_GSAT = `AR6 climate diagnostics|Surface Temperature (GSAT)|MAGICCv7.5.3|50.0th Percentile`,
         Year = as.numeric(Year)) %>%
  select(Scenario, Model, Name, Year, ar6IMP_GtCO2e, ar650pc_GSAT)

# AR6 C1
ar6c1 <- ar6 %>%
  left_join(metadata %>% select(Model, Scenario, Category, Category_name, Category_subset, Subset_Ch4, Ssp_family)) %>%
  filter(Variable %in% c(
    "Emissions|Kyoto Gases",
    "Carbon Sequestration|CCS",
    "Carbon Sequestration|Land Use",
    "AR6 climate diagnostics|Surface Temperature (GSAT)|MAGICCv7.5.3|50.0th Percentile"),
    Category == "C1") %>%
  pivot_longer(cols = matches("\\d{4}"), names_to = "Year") %>%
  select(-Unit) %>%
  pivot_wider(names_from = Variable, values_from = value) %>%
  mutate(ar6C1_GtCO2e = `Emissions|Kyoto Gases` / 1e3,
         ar6C1_CCS_GtCO2 = `Carbon Sequestration|CCS` / 1e3,
         ar6C1_LandSink_GtCO2 = `Carbon Sequestration|Land Use` / 1e3,
         ar6C1_50pcGSAT = `AR6 climate diagnostics|Surface Temperature (GSAT)|MAGICCv7.5.3|50.0th Percentile`,
         Year = as.numeric(Year)) %>%
  filter(Year >= 2020) %>%
  select(Scenario, Model, Category, Category_subset, Ssp_family, Year, ar6C1_GtCO2e, ar6C1_CCS_GtCO2, ar6C1_LandSink_GtCO2, ar6C1_50pcGSAT) %>%
  group_by(Scenario, Model, Category, Category_subset, Ssp_family) %>%
  complete(Year = 2020:2100) %>%
  group_by(Scenario, Model, Category) %>%
  mutate(ar6C1_GtCO2e = na.approx(ar6C1_GtCO2e, na.rm = TRUE, maxgap = 9),
         ar6C1_50pcGSAT = na.approx(ar6C1_50pcGSAT,  na.rm = TRUE, maxgap = 9),
         ar6C1_CCS_GtCO2 = na.approx(ar6C1_CCS_GtCO2, na.rm = TRUE, maxgap = 9),
         ar6C1_LandSink_GtCO2 = na.approx(ar6C1_LandSink_GtCO2, na.rm = TRUE, maxgap = 9))

# Rio Tinto 2022 - Historical Emissions Mismatch (pg. 9)
rt2022 <- tibble::tribble(
                         ~Year,         ~RT_GtCO2e,
              2000.44151624549,   36.7816091954023,
              2001.62454873646,   37.3946360153257,
              2002.52707581227,   38.9272030651341,
              2003.61010830325,   40.1532567049808,
               2004.3321299639,   41.3793103448276,
              2006.13718411552,   43.5249042145594,
              2006.13718411552,   43.5249042145594,
              2006.85920577617,   44.7509578544061,
              2007.94223826715,   45.3639846743295,
              2009.20577617328,   45.6704980842912,
              2010.28880866426,   47.5095785440613,
              2012.27436823105,   48.4291187739464,
               2012.9963898917,   49.0421455938697,
               2012.9963898917,   49.0421455938697,
              2014.25992779783,   49.9616858237548,
              2015.52346570397,   50.2681992337165,
               2017.3285198556,   51.4942528735632,
              2019.13357400722,    53.639846743295,
              2019.13357400722,    53.639846743295,
              2020.39711191336,    53.639846743295,
              2021.48014440433,   55.1724137931034,
              2022.92418772563,   54.8659003831418,
              2024.00722021661,   53.0268199233716,
              2029.06137184116,    41.992337164751,
              2030.32490974729,   38.9272030651341,
              2032.31046931408,   32.7969348659004,
              2035.19855595668,   26.0536398467433,
              2040.25270758123,   17.7777777777778,
              2045.12635379061,   7.35632183908046,
                          2050,                  0
            ) %>%
  mutate(Year = round(Year)) %>%
  complete(Year = 2000:2050) %>%
  mutate(RT_GtCO2e = zoo::na.approx(RT_GtCO2e, na.rm = FALSE))



rt2022 %>%
  left_join(histghg, by = "Year") %>%
  ggplot(aes(x = Year)) +
  geom_line(aes(y = ar6C1_GtCO2e, group = interaction(Model, Scenario)),
            colour = "grey",
            data = ar6c1 %>%
              filter(Ssp_family == 1) %>%
              na.omit(), show.legend = F) +
  geom_path(aes(y = RT_GtCO2e)) +
  geom_path(aes(y = GCP_GtCO2e), linetype = 2) +
  theme_bw()

ar6c1 %>%
  filter(Ssp_family == 1, grepl(Scenario, pattern = "19")) %>%
  pivot_longer(cols = c(ar6C1_GtCO2e, ar6C1_CCS_GtCO2, ar6C1_LandSink_GtCO2, ar6C1_50pcGSAT), names_to = "Variable", values_to = "Value") %>%
  ggplot(aes(x = Year, y = Value, group = interaction(Model, Scenario),
             colour = interaction(Model, Scenario))) +
  geom_path() +
  geom_path(aes(y = Value),
            data = rt2022 %>% select(Year, Value = RT_GtCO2e) %>% mutate(Variable = "ar6C1_GtCO2e",
                                                                         Model = "RioTinto 2022",
                                                                         Scenario = "Aspirational")) +

  geom_path(aes(y = Value),
            data = rt2022 %>% select(Year, Value = RT_GtCO2e) %>% mutate(Variable = "ar6C1_GtCO2e",
                                                                         Model = "RioTinto 2022",
                                                                         Scenario = "Aspirational") %>%
              filter(Year <= 2020), colour = "black") +
  scale_colour_brewer(type = "div") +
  facet_wrap(~fct_rev(Variable), scales = "free_y") +
  labs(x = NULL, y = NULL, colour = NULL) +
  theme_minimal() +
  theme(legend.position = "bottom")


