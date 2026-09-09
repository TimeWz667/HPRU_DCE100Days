library(readxl)
library(tidyverse)



# Parameters

n_sims <- 2000

# Load data

pop_f <- read_xlsx(here::here("data", "external", "ONS_EstPopulation_2024.xlsx"), sheet = "MYE2 - Females", skip = 7) 
pop_m <- read_xlsx(here::here("data", "external", "ONS_EstPopulation_2024.xlsx"), sheet = "MYE2 - Males", skip = 7) 

relig <- read_csv(here::here("data", "external", "ONS_CensusReligion_2021.csv"))
colnames(relig) <- c("Code", "Name", "Relig_code", "Relig", "N")


# Joining

dat_full <- bind_rows(
  pop_f %>% 
    filter(Geography == "Region") %>% 
    select(Code, Name, `0`:`90+`) %>% 
    mutate(Sex = "Female") %>% 
    pivot_longer(-c(Code, Name, Sex), names_to = "Age", values_to = "N"),
  pop_m %>% 
    filter(Geography == "Region") %>% 
    select(Code, Name, `0`:`90+`) %>% 
    mutate(Sex = "Male") %>% 
    pivot_longer(-c(Code, Name, Sex), names_to = "Age", values_to = "N")
) %>% 
  mutate(
    Age = ifelse(Age == "90+", 90, Age),
    Age = as.numeric(Age)
  ) %>% 
  left_join(
    relig %>% mutate(p = N / sum(N), .by = c(Name)) %>% select(Code, Relig, p),
    relationship = "many-to-many"
  )


dat_asr <- dat_full %>% 
  mutate(
    N = N * p
  ) %>% 
  filter(N > 0) %>% 
  filter(Age >= 18) %>% 
  group_by(Age, Sex, Relig) %>% 
  summarise(N = round(sum(N))) %>%
  ungroup() %>% 
  mutate(prop = N / sum(N)) %>% 
  select(-N)



# Sampling, 18+
set.seed(11667)

keys <- sample(1:nrow(dat_asr), n_sims, prob = dat_asr$prop, replace = T)

sims <- dat_asr[keys, ] %>%
  mutate(ID = 1:n()) %>% 
  select(Age, Sex, Religion = Relig)



sims %>% 
  mutate(Agp = cut(Age, c(18, seq(30, 100, 10)), right = F)) %>% 
  ggplot() +
  geom_bar(aes(x = Agp, fill = Religion))




write_csv(sims, file = here::here("data", "sims", "syn_pop_2000.csv"))




