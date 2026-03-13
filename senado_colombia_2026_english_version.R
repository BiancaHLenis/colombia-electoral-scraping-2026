# ============================================================
# COLOMBIA SENATE SCRAPER 2026
# Source: Registraduría Nacional del Estado Civil
# https://resultados.registraduria.gov.co
#
# Description: Extracts vote results by party and electoral
# participation data for the 2026 Senate election, by municipality.
#
# Output:
#   - df_senado.rds : dataset in R format
#   - senado_2026.xlsx : dataset in Excel format
#
# Author: BiancaHLenis
# Date: March 2026
#
# Legal note: This script consumes the Registraduría's public API.
# No personal credentials are stored.
# ============================================================


# ============================================================
# 1. LIBRARIES
# Loading the tools of the trade. Without these packages,
# this script is just a sad poem.
#   - httr     : handles HTTP requests (the script's mailman)
#   - jsonlite : converts JSON into R objects (the translator)
#   - dplyr    : data manipulation (the Swiss Army knife)
#   - writexl  : exports to Excel (for those who don't use R, bless them)
#   - stringr  : string cleaning (like tidying your apartment, but for text)
# ============================================================

library(httr)
library(jsonlite)
library(dplyr)
library(writexl)
library(stringr)


# ============================================================
# 2. HELPERS
# Small functions that save our lives repeatedly.
# Like that friend who always has a charger when yours dies.
# ============================================================

# %||% operator: returns 'a' if not NULL, otherwise returns 'b'.
# Equivalent to ?? in JavaScript or Python's "or".
# Usage: value <- json_field %||% NA
# Without this, a single NULL field crashes the entire dataframe. Drama avoided.
`%||%` <- function(a, b) if (!is.null(a)) a else b

# limpiar_pct: converts Colombian percentage strings to numeric.
# The Registraduría uses commas as decimal separators (e.g. "25,69%").
# R expects dots. We have to negotiate between the two.
# Steps: remove % symbol, replace comma with dot, convert to numeric.
limpiar_pct <- function(x) {
    as.numeric(str_replace_all(x, c("%" = "", "," = ".")))
}


# ============================================================
# 3. HTTP HEADERS
#
# So the server treats us like people and doesn't block us
# like robots (even though technically we are robots).
#
# User-Agent: we tell the server we're a normal Mac browser.
# Spoiler: we're not.
#
# Cookie: The Registraduría uses Cloudflare as a bouncer.
# The cf_clearance is the VIP pass Cloudflare issues after
# verifying you're human. It expires periodically.
#
# ⚠️  IMPORTANT: If the scraper starts returning NULL for all
# municipalities, the cookie has likely expired.
# To renew it:
#   1. Open Chrome and go to resultados.registraduria.gov.co
#   2. Open DevTools (F12) → Network tab
#   3. Reload the page and click on any request to the domain
#   4. In the request headers, copy the full value of Cookie
#   5. Replace the value of 'Cookie' below
# ============================================================

headers <- c(
    'User-Agent' = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    'Cookie'     = 'cf_clearance=YOUR_COOKIE_HERE'
    # ^ Replace YOUR_COOKIE_HERE with a fresh cookie from your session.
    # See instructions above. Never push your real cookie to GitHub.
)

# get_json: generic function that performs a GET request and parses JSON.
# Returns the R object if successful, NULL if something fails.
# tryCatch prevents a single municipality error from crashing the whole loop.
# Life lesson: always handle your errors, in code and in general.
get_json <- function(url) {
    tryCatch({
        resp <- GET(url, add_headers(.headers = headers))
        if (status_code(resp) == 200) {
            # rawToChar converts response bytes to text
            # fromJSON transforms it into an R list
            # simplifyVector = FALSE keeps everything as a list (more predictable)
            fromJSON(rawToChar(resp$content), simplifyVector = FALSE)
        } else {
            NULL  # The server said no. We respect that.
        }
    }, error = function(e) NULL)
}


# ============================================================
# 4. EXTRACTION FUNCTIONS
# The main logic lives here. Two functions: one for votes
# by party and one for participation data.
# Kept separate because the JSON has two different structures
# and mixing them would be a telenovela-worthy disaster.
# ============================================================

# extraer_senado: extracts votes by party for a given municipality.
#
# URL pattern: /json/ACT/SE/{municipality_code}.json
# Where SE = Senado (Senate), ACT = current results (not projected).
#
# Relevant JSON structure:
#   data
#   └── camaras[[1]]          ← legislative chamber (Senate in this case)
#       └── partotabla        ← list of parties with their votes
#           └── [[i]]
#               └── act
#                   ├── codpar  ← numeric party code
#                   ├── vot     ← absolute votes
#                   └── pvot    ← vote percentage (string with comma)
#
# Returns a dataframe with one row per party, or NULL if no data.
extraer_senado <- function(cod_municipio) {
    url   <- paste0("https://resultados.registraduria.gov.co/json/ACT/SE/", cod_municipio, ".json")
    datos <- get_json(url)
    
    # Defensive checks: if any level of the hierarchy is missing,
    # return NULL instead of throwing a cryptic error.
    if (is.null(datos) || is.null(datos$camaras) || length(datos$camaras) == 0) return(NULL)
    
    senado <- datos$camaras[[1]]  # take the first (and only) element: Senate
    if (is.null(senado$partotabla) || length(senado$partotabla) == 0) return(NULL)
    
    # Iterate over each party in the list and build one dataframe per party.
    # lapply returns a list of dataframes; bind_rows stacks them into one.
    lapply(senado$partotabla, function(p) {
        data.frame(
            cod_municipio = cod_municipio,
            cod_partido   = p$act$codpar %||% NA,
            votos         = as.numeric(p$act$vot  %||% 0),
            pct           = p$act$pvot  %||% NA,   # cleaned later with limpiar_pct()
            stringsAsFactors = FALSE
        )
    }) %>% bind_rows()
}


# extraer_participacion_senado: extracts electoral participation metrics.
#
# ⚠️  JSON trap: there are TWO levels of totals and they are NOT the same.
#
#   datos$totales$act              → GLOBAL totals (all constituencies)
#                                    Use for: electoral census and total voters.
#                                    This is what the TOP BAR of the website shows.
#
#   datos$camaras[[1]]$totales$act → NATIONAL/TERRITORIAL constituency totals
#                                    Use for: null votes, unmarked, valid, blank.
#                                    This is what the FOOTER of the website shows.
#
# Mixing the two levels produces incorrect participation percentages.
# Here they are intentionally combined to replicate what the official website shows.
extraer_participacion_senado <- function(cod_municipio) {
    url   <- paste0("https://resultados.registraduria.gov.co/json/ACT/SE/", cod_municipio, ".json")
    datos <- get_json(url)
    
    if (is.null(datos) || is.null(datos$camaras) || length(datos$camaras) == 0) return(NULL)
    
    t_total <- datos$totales$act                   # root level: census and total voters
    t       <- datos$camaras[[1]]$totales$act      # territorial level: vote quality
    if (is.null(t)) return(NULL)
    
    data.frame(
        cod_municipio      = cod_municipio,
        # ── From root level (all constituencies) ──────────────────────────
        censo              = as.numeric(t_total$centota  %||% NA),   # registered voters
        votantes_total     = as.numeric(t_total$votant   %||% NA),   # people who actually voted
        pct_votantes_total = limpiar_pct(t_total$pvotant %||% NA),   # % total turnout
        # ── From territorial level (national constituency) ─────────────────
        votantes           = as.numeric(t$votant   %||% NA),         # voters in territorial circ.
        pct_votantes       = limpiar_pct(t$pvotant  %||% NA),
        votos_nulos        = as.numeric(t$votnul   %||% NA),         # null votes (the angry ones)
        pct_nulos          = limpiar_pct(t$pvotnul  %||% NA),
        votos_no_marcados  = as.numeric(t$votnma   %||% NA),         # blank ballots with nothing marked
        pct_no_marcados    = limpiar_pct(t$pvotnma  %||% NA),
        votos_blanco       = as.numeric(t$votbla   %||% NA),         # intentional blank vote
        pct_blanco         = limpiar_pct(t$pvotbla  %||% NA),
        votos_validos      = as.numeric(t$votval   %||% NA),         # valid = to parties + blank
        pct_validos        = limpiar_pct(t$pvotval  %||% NA),
        votos_a_partidos   = as.numeric(t$votcan   %||% NA),         # votes that actually count for seats
        pct_a_partidos     = limpiar_pct(t$pvotcan  %||% NA),
        stringsAsFactors   = FALSE
    )
}


# ============================================================
# 5. MUNICIPALITY NOMENCLATOR
#
# The Registraduría has a master JSON with all municipalities
# and their codes. We download it once at the start.
# Think of it as the phone book for the Colombian state.
#
# JSON structure:
#   nom$amb[[1]]$ambitos → list of geographic entities with levels:
#     l == 1 : country
#     l == 2 : department
#     l == 3 : municipality  ← these are what we need
#
# Each entity has:
#   co : code (e.g. "01001" for Medellín)
#   n  : name
#   l  : geographic level
# ============================================================

nom_raw  <- GET(
    "https://resultados.registraduria.gov.co/json/nomenclator.json",
    add_headers(.headers = headers)
)
nom      <- fromJSON(rawToChar(nom_raw$content), simplifyVector = FALSE)
ambitos  <- nom[["amb"]][[1]][["ambitos"]]

# Keep only municipalities (level 3).
# Filter() is like dplyr::filter() but for base R lists.
municipios_nom <- Filter(function(x) x[["l"]] == 3, ambitos)

# Build the municipalities dataframe.
# substr(..., 1, 4) extracts the first 4 characters of the code,
# which correspond to the department code.
df_municipios <- data.frame(
    cod_municipio = sapply(municipios_nom, function(x) x[["co"]]),
    municipio     = sapply(municipios_nom, function(x) x[["n"]]),
    cod_depto     = substr(sapply(municipios_nom, function(x) x[["co"]]), 1, 4),
    stringsAsFactors = FALSE
)

# Manual department dictionary.
# Yes, it's long. No, there's no better API for this.
# Colombia has 32 departments + Bogotá D.C. + overseas consulates.
deptos_nombres <- list(
    "0100"="ANTIOQUIA",          "0300"="ATLANTICO",
    "1600"="BOGOTA D.C.",        "0500"="BOLIVAR",
    "0700"="BOYACA",             "0900"="CALDAS",
    "4400"="CAQUETA",            "4600"="CASANARE",
    "1100"="CAUCA",              "1200"="CESAR",
    "1700"="CHOCO",              "1300"="CORDOBA",
    "1500"="CUNDINAMARCA",       "5000"="GUAINIA",
    "5400"="GUAVIARE",           "1900"="HUILA",
    "4800"="LA GUAJIRA",         "2100"="MAGDALENA",
    "5200"="META",               "2300"="NARINO",
    "2500"="NORTE DE SANTANDER", "6400"="PUTUMAYO",
    "2600"="QUINDIO",            "2400"="RISARALDA",
    "5600"="SAN ANDRES",         "2700"="SANTANDER",
    "2800"="SUCRE",              "2900"="TOLIMA",
    "3100"="VALLE",              "6800"="VAUPES",
    "7200"="VICHADA",            "4000"="ARAUCA",
    "6000"="AMAZONAS",           "8800"="CONSULADOS"
)

# sapply iterates over each department code and translates it to a name.
# If the code is not in the dictionary, return the code itself —
# better a weird value than a lost one.
df_municipios$departamento <- sapply(df_municipios$cod_depto, function(x) {
    nombre <- deptos_nombres[[x]]
    if (is.null(nombre)) x else nombre
})

cat("Municipalities loaded:", nrow(df_municipios), "\n")
# If you see ~1189 municipalities, everything is fine.
# If you see fewer, something went wrong above.


# ============================================================
# 6. SCRAPING LOOP
#
# The heart of the script. Iterates over ~1,189 municipalities
# one by one and extracts votes + participation for each.
#
# Loop design:
#   - Two separate lists (votes and participation) to accumulate results.
#     Lists are more efficient than running bind_rows() on every iteration.
#   - 'errores' vector to log municipalities that failed.
#   - Automatic backup every 200 municipalities. Because the power goes out,
#     the internet drops, and computers do whatever they want.
#     The backup is your life insurance.
#   - Sys.sleep(0.3): 0.3-second pause between requests. Basic server etiquette.
#     Without this you're that guest who shows up and eats everything at the buffet.
#
# Estimated time: ~1,189 municipalities × 0.3s = ~6 minutes.
# Go get a coffee. The script doesn't need you.
# ============================================================

df_votos_list <- list()   # accumulates vote-by-party dataframes
df_part_list  <- list()   # accumulates participation dataframes
errores       <- c()      # stores codes of municipalities that failed
total         <- nrow(df_municipios)

for (i in seq_len(total)) {
    cod   <- df_municipios$cod_municipio[i]
    muni  <- df_municipios$municipio[i]
    depto <- df_municipios$departamento[i]
    
    # Print progress every 50 municipalities to confirm the script is alive.
    # Complete silence in a long loop means something is wrong (or it finished).
    if (i %% 50 == 0) cat(sprintf("[%d/%d] %s - %s\n", i, total, depto, muni))
    
    # ── Votes by party ─────────────────────────────────────────────────────
    # Extra tryCatch in case extraer_senado() throws an uncontemplate error.
    # (get_json() already handles HTTP errors, but this covers edge cases)
    votos <- tryCatch(extraer_senado(cod), error = function(e) NULL)
    if (!is.null(votos) && nrow(votos) > 0) {
        df_votos_list[[cod]] <- votos   # store with the code as element name
    } else {
        errores <- c(errores, cod)      # log the failure for later inspection
    }
    
    # ── Electoral participation ────────────────────────────────────────────
    part <- tryCatch(extraer_participacion_senado(cod), error = function(e) NULL)
    if (!is.null(part)) df_part_list[[cod]] <- part
    
    # ── Automatic backup every 200 municipalities ──────────────────────────
    # saveRDS saves R objects in a compressed binary format.
    # Faster and more faithful than CSV for nested lists.
    # Adjust the path if your downloads folder is different.
    if (i %% 200 == 0) {
        saveRDS(df_votos_list, "~/Downloads/elecciones 2026/backup_senado_votos.rds")
        saveRDS(df_part_list,  "~/Downloads/elecciones 2026/backup_senado_part.rds")
        cat("  💾 Backup saved at iteration", i, "\n")
    }
    
    Sys.sleep(0.3)  # courtesy pause. The server needs to breathe too.
}

# bind_rows() stacks all dataframes from the list into one.
# This is the moment where all the loop's hard work becomes a beautiful dataframe.
df_votos <- bind_rows(df_votos_list)
df_part  <- bind_rows(df_part_list)

cat("Municipalities with votes:", length(df_votos_list), "\n")
cat("Municipalities with participation:", length(df_part_list), "\n")
cat("Errors (municipalities without data):", length(errores), "\n")
# Some municipalities may have no data if the Registraduría hasn't reported them yet.
# Check 'errores' to see which ones. Likely very small municipalities
# or special constituencies that use a different endpoint.


# ============================================================
# 7. BUILDING THE FINAL DATAFRAME
#
# We join votes + municipalities + participation into a single table.
# Then map party codes to readable names and group them into
# political families for strategic analysis.
#
# case_when() is dplyr's switch/case. Reads top to bottom and
# assigns the first matching condition. TRUE at the end is the "default".
#
# Political families: custom grouping based on historical coalition
# behavior. Not official — analytical.
# ============================================================

df_senado_final <- df_votos %>%
    # left_join preserves all records from df_votos even without a match.
    # There should always be a match here since codes come from the same nomenclator.
    left_join(df_municipios, by = "cod_municipio") %>%
    left_join(df_part,       by = "cod_municipio") %>%
    mutate(
        # ── Party name ────────────────────────────────────────────────────
        # Codes are assigned by the Registraduría and are nationally consistent
        # for the Senate. For the House they may vary by constituency.
        partido = case_when(
            cod_partido == "10"  ~ "PARTIDO CENTRO DEMOCRATICO",
            cod_partido == "2"   ~ "PARTIDO CONSERVADOR COLOMBIANO",
            cod_partido == "1"   ~ "PARTIDO LIBERAL COLOMBIANO",
            cod_partido == "3"   ~ "PARTIDO CAMBIO RADICAL",
            cod_partido == "9"   ~ "PARTIDO DE LA U",
            cod_partido == "92"  ~ "PACTO HISTORICO SENADO",
            cod_partido == "4"   ~ "PARTIDO ALIANZA VERDE",
            cod_partido == "7"   ~ "PARTIDO MIRA",
            cod_partido == "17"  ~ "MOVIMIENTO SALVACION NACIONAL",
            cod_partido == "16"  ~ "PARTIDO NUEVO LIBERALISMO",
            cod_partido == "6"   ~ "PARTIDO ASI",
            cod_partido == "14"  ~ "PARTIDO COLOMBIA JUSTA LIBRES",
            cod_partido == "11"  ~ "MOVIMIENTO MAIS",
            TRUE ~ paste0("PARTIDO_", cod_partido)  # unknown code: named after its code
        ),
        # ── Political family ──────────────────────────────────────────────
        # Grouping into blocs for coalition and electoral behavior analysis.
        # Useful for aggregating votes by tendency rather than individual party.
        familia = case_when(
            partido == "PARTIDO CENTRO DEMOCRATICO"       ~ "GRAN CONSULTA CD",
            partido %in% c("PARTIDO CONSERVADOR COLOMBIANO",
                           "PARTIDO LIBERAL COLOMBIANO",
                           "PARTIDO CAMBIO RADICAL",
                           "PARTIDO DE LA U")             ~ "GRAN CONSULTA POTENCIAL",
            partido == "PACTO HISTORICO SENADO"           ~ "PACTO HISTORICO",
            partido %in% c("PARTIDO ALIANZA VERDE",
                           "MOVIMIENTO SALVACION NACIONAL",
                           "PARTIDO NUEVO LIBERALISMO",
                           "PARTIDO MIRA",
                           "PARTIDO COLOMBIA JUSTA LIBRES") ~ "CENTRO INDEPENDIENTE",
            partido == "MOVIMIENTO MAIS"                  ~ "CIRCUNSCRIPCION ESPECIAL",
            TRUE ~ "OTRO"
        )
    )


# ============================================================
# 8. SAVE OUTPUTS
#
# Two formats:
#   .rds  → for continued work in R (fast, compressed, type-faithful)
#   .xlsx → to share with humans who use Excel (welcome, no judgment)
#
# writexl::write_xlsx() accepts a named list of dataframes,
# where each element becomes a sheet in the Excel file.
# Only one sheet here ("partidos"), but the structure makes it easy
# to add more (e.g. list(partidos = ..., participacion = ...)).
#
# Adjust the paths if you store your data elsewhere.
# ============================================================

saveRDS(df_senado_final, "~/Downloads/elecciones 2026/df_senado.rds")

writexl::write_xlsx(
    list(
        partidos = df_senado_final %>%
            # distinct() removes duplicates. Repeated rows can appear if
            # the loop processed a municipality more than once (rare but possible).
            distinct(cod_municipio, municipio, departamento,
                     cod_partido, partido, familia, votos, pct,
                     censo, votantes_total, pct_votantes_total,
                     votantes, pct_votantes, votos_validos, votos_nulos,
                     votos_no_marcados, votos_blanco, pct_blanco,
                     votos_a_partidos, pct_a_partidos)
    ),
    "~/Downloads/elecciones 2026/senado_2026.xlsx"
)

# Final summary. If the numbers look off, something went wrong above.
# ~1,189 municipalities × ~13 parties = ~15,000 rows is expected.
cat("Total rows:", nrow(df_senado_final), "\n")
cat("Unique municipalities:", n_distinct(df_senado_final$cod_municipio), "\n")
cat("Unique parties:", n_distinct(df_senado_final$partido), "\n")
cat("All saved to ~/Downloads/elecciones 2026/ ✓\n")
cat("Time to make pretty charts. You earned it.\n")
