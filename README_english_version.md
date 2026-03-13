# 🗳️ Colombia Electoral Scraper 2026

Automated extraction of Colombian Senate electoral results from the public API of the Registraduría Nacional del Estado Civil.

---

## What does this script do?

Iterates over **~1,189 municipalities** in Colombia, queries the Registraduría API one municipality at a time, and builds a dataset with:

- **Votes by party** in each municipality
- **Electoral participation**: census, voters, null votes, blank votes, unmarked ballots, valid votes
- **Party classification** into political families for coalition analysis

The final output is two analysis-ready files: `.rds` (R) and `.xlsx` (Excel).

---

## Data source

**Registraduría Nacional del Estado Civil de Colombia**  
🔗 https://resultados.registraduria.gov.co  
Legislative elections — March 2026

---

## Repository structure

```
colombia-electoral-scraping-2026/
│
├── senado_colombia_2026.R      # Main scraping script (Spanish)
├── senado_colombia_2026_EN.R   # Main scraping script (English)
├── README.md                   # This file (English)
└── README_ES.md                # Documentation in Spanish
```

---

## Requirements

**R >= 4.0** and the following packages:

```r
install.packages(c("httr", "jsonlite", "dplyr", "writexl", "stringr"))
```

---

## How to use it

### 1. Renew the Cloudflare cookie

The Registraduría uses Cloudflare as protection. The script needs an active session cookie to work:

1. Open Chrome and go to `resultados.registraduria.gov.co`
2. Open DevTools (`F12`) → **Network** tab
3. Reload the page and click on any request to the domain
4. In the request headers, copy the full value of `Cookie`
5. Paste it in the script where it says `YOUR_COOKIE_HERE`

> ⚠️ Never push your real cookie to GitHub. It expires periodically — if the script returns NULL for all municipalities, it's time to renew it.

### 2. Adjust output paths

In section 8 of the script, change the paths if your downloads folder is different:

```r
saveRDS(df_senado_final, "~/Downloads/elecciones 2026/df_senado.rds")
writexl::write_xlsx(...,  "~/Downloads/elecciones 2026/senado_2026.xlsx")
```

### 3. Run the script

```r
source("senado_colombia_2026_EN.R")
```

Estimated time: **~6 minutes** (~1,189 municipalities × 0.3s pause per request).  
Go get a coffee. The script doesn't need you.

---

## Output variables

| Variable | Description |
|---|---|
| `cod_municipio` | Official municipality code (Registraduría) |
| `municipio` | Municipality name |
| `departamento` | Department name |
| `cod_partido` | Numeric party code |
| `partido` | Full party name |
| `familia` | Political family (analytical grouping) |
| `votos` | Absolute votes for the party in the municipality |
| `pct` | Vote share of the party |
| `censo` | Total registered voters |
| `votantes_total` | Total people who voted |
| `pct_votantes_total` | % voter turnout |
| `votos_nulos` | Null votes |
| `votos_blanco` | Intentional blank votes |
| `votos_no_marcados` | Unmarked ballots |
| `votos_validos` | Valid votes (to parties + blank) |
| `votos_a_partidos` | Votes that count toward seats |

---

## Political families

The script classifies parties into blocs to facilitate coalition analysis:

| Family | Parties |
|---|---|
| `GRAN CONSULTA CD` | Centro Democrático |
| `GRAN CONSULTA POTENCIAL` | Conservador, Liberal, Cambio Radical, De la U |
| `PACTO HISTORICO` | Pacto Histórico Senado |
| `CENTRO INDEPENDIENTE` | Alianza Verde, Nuevo Liberalismo, MIRA, Colombia Justa Libres, Salvación Nacional |
| `CIRCUNSCRIPCION ESPECIAL` | MAIS |

> This classification is **analytical**, not official. It reflects coalition behavior observed in the 2022–2026 electoral cycle.

---

## Technical note on JSON total levels

The Registraduría's JSON has **two levels of totals** that are not interchangeable:

- `datos$totales$act` → global totals (all constituencies). Used for **census and total voters**.
- `datos$camaras[[1]]$totales$act` → national/territorial constituency. Used for **null, blank, and valid votes**.

Mixing them produces incorrect percentages. The script uses them intentionally according to what the official web interface displays.

---

## Author

**BiancaHLenis**  
🔗 [github.com/BiancaHLenis](https://github.com/BiancaHLenis)
