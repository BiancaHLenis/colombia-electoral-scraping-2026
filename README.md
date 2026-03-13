# 🗳️ Scraper Senado Colombia 2026

Extracción automatizada de resultados electorales del Senado colombiano desde la API pública de la Registraduría Nacional del Estado Civil.

---

## ¿Qué hace este script?

Recorre los **~1,189 municipios** de Colombia, consulta la API de la Registraduría municipio por municipio, y construye una base de datos con:

- **Votos por partido** en cada municipio
- **Participación electoral**: censo, votantes, nulos, blancos, no marcados, válidos
- **Clasificación de partidos** en familias políticas para análisis de coaliciones

El output final son dos archivos listos para analizar: `.rds` (R) y `.xlsx` (Excel).

---

## Fuente de datos

**Registraduría Nacional del Estado Civil de Colombia**  
🔗 https://resultados.registraduria.gov.co  
Elecciones legislativas — Marzo 2026

---

## Estructura del repositorio

```
colombia-electoral-scraping/
│
├── senado_colombia_2026.R   # Script principal de scraping
└── README.md                # Este archivo
```

---

## Requisitos

**R >= 4.0** y los siguientes paquetes:

```r
install.packages(c("httr", "jsonlite", "dplyr", "writexl", "stringr"))
```

---

## Cómo usarlo

### 1. Renovar la cookie de Cloudflare

La Registraduría usa Cloudflare como protección. Para que el script funcione necesitas una cookie de sesión activa:

1. Abre Chrome y ve a `resultados.registraduria.gov.co`
2. Abre DevTools (`F12`) → pestaña **Network**
3. Recarga la página y haz clic en cualquier request al dominio
4. En los headers del request, copia el valor completo de `Cookie`
5. Pégalo en el script donde dice `TU_COOKIE_AQUI`

> ⚠️ No subas tu cookie real a GitHub. Expira periódicamente — si el script devuelve NULL en todos los municipios, es hora de renovarla.

### 2. Ajustar las rutas de output

En la sección 8 del script, cambia las rutas si tu carpeta de descargas es diferente:

```r
saveRDS(df_senado_final, "~/Downloads/elecciones 2026/df_senado.rds")
writexl::write_xlsx(...,  "~/Downloads/elecciones 2026/senado_2026.xlsx")
```

### 3. Correr el script

```r
source("senado_colombia_2026.R")
```

Tiempo estimado: **~6 minutos** (~1,189 municipios × 0.3s de pausa por request).  
Ve por un café. El script no te necesita.

---

## Variables del output

| Variable | Descripción |
|---|---|
| `cod_municipio` | Código oficial del municipio (Registraduría) |
| `municipio` | Nombre del municipio |
| `departamento` | Nombre del departamento |
| `cod_partido` | Código numérico del partido |
| `partido` | Nombre completo del partido |
| `familia` | Familia política (agrupación analítica) |
| `votos` | Votos absolutos del partido en el municipio |
| `pct` | Porcentaje de votos del partido |
| `censo` | Total de personas habilitadas para votar |
| `votantes_total` | Total de personas que votaron |
| `pct_votantes_total` | % de participación |
| `votos_nulos` | Votos nulos |
| `votos_blanco` | Votos en blanco intencionales |
| `votos_no_marcados` | Tarjetas sin marcar |
| `votos_validos` | Votos válidos (a partidos + blanco) |
| `votos_a_partidos` | Votos que cuentan para curules |

---

## Familias políticas

El script clasifica los partidos en bloques para facilitar el análisis de coaliciones:

| Familia | Partidos |
|---|---|
| `GRAN CONSULTA CD` | Centro Democrático |
| `GRAN CONSULTA POTENCIAL` | Conservador, Liberal, Cambio Radical, De la U |
| `PACTO HISTORICO` | Pacto Histórico Senado |
| `CENTRO INDEPENDIENTE` | Alianza Verde, Nuevo Liberalismo, MIRA, Colombia Justa Libres, Salvación Nacional |
| `CIRCUNSCRIPCION ESPECIAL` | MAIS |

> Esta clasificación es **analítica**, no oficial. Refleja el comportamiento coalicional observado en el ciclo electoral 2022-2026.

---

## Nota técnica sobre los niveles de totales

El JSON de la Registraduría tiene **dos niveles de totales** que no son intercambiables:

- `datos$totales$act` → totales globales (todas las circunscripciones). Se usa para **censo y votantes totales**.
- `datos$camaras[[1]]$totales$act` → circunscripción nacional/territorial. Se usa para **nulos, blancos, válidos**.

Mezclarlos produce porcentajes incorrectos. El script los usa intencionalmente según lo que muestra la interfaz web oficial.

---

## Autor

**BiancaHLenis**  
🔗 [github.com/BiancaHLenis](https://github.com/BiancaHLenis)
