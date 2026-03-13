# Scraping Electoral Colombia 2026

Extracción automatizada de resultados electorales legislativos colombianos desde la API pública de la Registraduría Nacional del Estado Civil. Cubre Senado y Cámara de Representantes.

---

## ¿Qué contiene este repositorio?

| Script | Descripción | Output |
|---|---|---|
| `senado_colombia_2026.R` | Votos por partido y participación electoral para los ~1,189 municipios. Circunscripción nacional. | `df_senado.rds`, `senado_2026.xlsx` |
| `camara_colombia_2026.R` | Votos por partido y candidato para los ~1,189 municipios. Circunscripción territorial departamental. | `df_camara.rds`, `camara_2026.xlsx` |

Ambos scripts extraen para cada municipio:

- **Votos por partido** (y por candidato en el caso de la Cámara)
- **Participación electoral**: censo, votantes, nulos, blancos, no marcados, válidos
- **Clasificación de partidos** en familias políticas para análisis de coaliciones

---

## Diferencia entre Senado y Cámara

El Senado tiene circunscripción **nacional** — todos los colombianos votan por los mismos partidos. La Cámara tiene circunscripción **departamental** — cada departamento tiene sus propias listas y coaliciones locales. Esto explica por qué el diccionario de partidos de la Cámara tiene más de 100 entradas. No es un error. Es Colombia.

---

## Fuente de datos

**Registraduría Nacional del Estado Civil de Colombia**  
https://resultados.registraduria.gov.co  
Elecciones legislativas — Marzo 2026

---

## Estructura del repositorio

```
colombia-electoral-scraping-2026/
│
├── senado_colombia_2026.R                   # Scraper Senado (español)
├── senado_colombia_2026_english_version.R   # Scraper Senado (inglés)
├── camara_colombia_2026.R                   # Scraper Cámara (español)
├── README.md                                # Este archivo
└── README_english_version.md               # Documentación en inglés
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

La Registraduría usa Cloudflare como protección. Para que los scripts funcionen necesitas una cookie de sesión activa:

1. Abre Chrome y ve a `resultados.registraduria.gov.co`
2. Abre DevTools (`F12`) → pestaña **Network**
3. Recarga la página y haz clic en cualquier request al dominio
4. En los headers del request, copia el valor completo de `Cookie`
5. Pégalo en el script donde dice `PEGAR_AQUI_LA_COOKIE`

> No subas tu cookie real a GitHub. Expira periódicamente — si el script devuelve NULL en todos los municipios, es hora de renovarla.

### 2. Ajustar las rutas de output

En la sección 8 de cada script, cambia las rutas si tu carpeta de descargas es diferente:

```r
saveRDS(df_senado_final, "~/Downloads/elecciones 2026/df_senado.rds")
saveRDS(df_camara_final, "~/Downloads/elecciones 2026/df_camara.rds")
```

### 3. Correr los scripts

```r
source("senado_colombia_2026.R")
source("camara_colombia_2026.R")
```

Tiempo estimado por script: **~6 minutos** (~1,189 municipios × 0.3s de pausa por request).

---

## Variables del output — Senado

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

## Variables del output — Cámara (adicionales)

| Variable | Descripción |
|---|---|
| `codpar` | Código del partido o coalición departamental |
| `vot_partido` | Votos totales del partido en el municipio |
| `codcan` | Código del candidato (`"0"` = voto solo por lista) |
| `cedula` | Cédula del candidato |
| `candidato` | Nombre completo del candidato |
| `vot_candidato` | Votos recibidos por el candidato |
| `carg` | `"1"` si el candidato ganó curul, `"0"` si no |

---

## Familias políticas

Clasificación analítica para facilitar el análisis de coaliciones:

| Familia | Partidos principales |
|---|---|
| `GRAN CONSULTA CD` | Centro Democrático y alianzas |
| `GRAN CONSULTA POTENCIAL` | Conservador, Liberal, Cambio Radical, De la U |
| `PACTO HISTORICO` | Pacto Histórico y coaliciones afines |
| `CENTRO INDEPENDIENTE` | Alianza Verde, Nuevo Liberalismo, MIRA, Salvación Nacional |
| `CIRCUNSCRIPCION ESPECIAL` | MAIS y circunscripciones étnicas |

> Esta clasificación es **analítica**, no oficial. Refleja el comportamiento coalicional observado en el ciclo electoral 2022-2026.

---

## Nota técnica sobre los niveles de totales

El JSON de la Registraduría tiene **dos niveles de totales** que no son intercambiables:

- `datos$totales$act` → totales globales (todas las circunscripciones). Se usa para **censo y votantes totales**.
- `datos$camaras[[1]]$totales$act` → circunscripción nacional/territorial. Se usa para **nulos, blancos, válidos**.

Mezclarlos produce porcentajes incorrectos. Los scripts los usan intencionalmente según lo que muestra la interfaz web oficial.

---

## Autor

**BiancaHLenis**  
[github.com/BiancaHLenis](https://github.com/BiancaHLenis)
