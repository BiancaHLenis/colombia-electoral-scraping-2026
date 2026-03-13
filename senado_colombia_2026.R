# ============================================================
# SCRAPER SENADO COLOMBIA 2026
# Fuente: Registraduría Nacional del Estado Civil
# https://resultados.registraduria.gov.co
#
# Descripción: Extrae resultados de votos por partido y datos
# de participación electoral para Senado 2026, por municipio.
#
# Output:
#   - df_senado.rds : base de datos en formato R
#   - senado_2026.xlsx : base de datos en Excel
#
# Autor: BiancaHLenis
# Fecha: Marzo 2026
#
# Nota legal: Este script consume la API pública de la
# Registraduría. No se almacenan credenciales personales.
# ============================================================


# ============================================================
# 1. LIBRERÍAS
# Cargamos las herramientas del oficio. Sin estas librerías
# este script es solo un poema triste.
#   - httr     : hace las peticiones HTTP (el cartero del script)
#   - jsonlite : convierte JSON en objetos R (el traductor)
#   - dplyr    : manipulación de datos (la navaja suiza)
#   - writexl  : exporta a Excel (para los que no usan R, los pobres)
#   - stringr  : limpieza de strings (como limpiar el apartamento pero para texto)
# ============================================================

library(httr)
library(jsonlite)
library(dplyr)
library(writexl)
library(stringr)


# ============================================================
# 2. HELPERS
# Funciones pequeñas que nos salvan la vida repetidamente.
# Como ese amigo que siempre tiene cargador cuando el tuyo murió.
# ============================================================

# Operador %||%: si 'a' no es NULL retorna 'a', si es NULL retorna 'b'.
# Equivale al operador ?? de JavaScript o Python's "or".
# Uso: valor <- dato_del_json %||% NA
# Sin esto, un solo campo NULL tumba todo el dataframe. Drama evitado.
`%||%` <- function(a, b) if (!is.null(a)) a else b

# limpiar_pct: convierte strings de porcentaje colombiano a numérico.
# La Registraduría usa comas como decimales (ej: "25,69%").
# R espera puntos. Hay que negociar entre los dos.
# Pasos: elimina el símbolo %, reemplaza coma por punto, convierte a numeric.
limpiar_pct <- function(x) {
    as.numeric(str_replace_all(x, c("%" = "", "," = ".")))
}


# ============================================================
# 3. HEADERS HTTP
#
# Para que el servidor nos atienda como personas y no nos
# bloquee como robots (aunque técnicamente somos robots).
#
# User-Agent: le decimos al servidor que somos un navegador
# normal de Mac. Spoiler: no lo somos.
#
# Cookie: La Registraduría usa Cloudflare como guardaespaldas.
# El cf_clearance es el pase VIP que Cloudflare entrega después
# de verificar que eres humano. Caduca periódicamente.
#
# ⚠️  IMPORTANTE: Si el scraper empieza a retornar NULL en todos
# los municipios, es probable que la cookie haya expirado.
# Para renovarla:
#   1. Abre Chrome y ve a resultados.registraduria.gov.co
#   2. Abre DevTools (F12) → pestaña Network
#   3. Recarga la página y busca cualquier petición al dominio
#   4. En los headers del request, copia el valor de Cookie
#   5. Reemplaza el valor de 'Cookie' aquí abajo
# ============================================================

headers <- c(
    'User-Agent' = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    'Cookie'     = 'cf_clearance=TU_COOKIE_AQUI'
    # ^ Reemplaza TU_COOKIE_AQUI con una cookie fresca de tu sesión.
    # Ver instrucciones arriba. No subas tu cookie real a GitHub.
)

# get_json: función genérica que hace una petición GET y parsea el JSON.
# Retorna el objeto R si todo sale bien, NULL si algo falla.
# El tryCatch evita que un solo municipio con error tumbe el loop completo.
# Lección de vida: siempre maneja tus errores, en el código y en general.
get_json <- function(url) {
    tryCatch({
        resp <- GET(url, add_headers(.headers = headers))
        if (status_code(resp) == 200) {
            # rawToChar convierte los bytes de la respuesta a texto
            # fromJSON lo transforma en lista de R
            # simplifyVector = FALSE mantiene todo como lista (más predecible)
            fromJSON(rawToChar(resp$content), simplifyVector = FALSE)
        } else {
            NULL  # El servidor nos dijo que no. Respetamos.
        }
    }, error = function(e) NULL)
}


# ============================================================
# 4. FUNCIONES DE EXTRACCIÓN
# Aquí vive la lógica principal. Dos funciones: una para votos
# por partido y otra para datos de participación.
# Separadas porque el JSON tiene dos estructuras distintas
# y mezclarlas sería una pesadilla digna de telenovela.
# ============================================================

# extraer_senado: extrae votos por partido para un municipio.
#
# URL patrón: /json/ACT/SE/{cod_municipio}.json
# Donde SE = Senado, ACT = resultados actuales (no proyectados).
#
# Estructura relevante del JSON:
#   datos
#   └── camaras[[1]]          ← cámara legislativa (Senado en este caso)
#       └── partotabla        ← lista de partidos con sus votos
#           └── [[i]]
#               └── act
#                   ├── codpar  ← código numérico del partido
#                   ├── vot     ← votos absolutos
#                   └── pvot    ← porcentaje de votos (string con coma)
#
# Retorna un dataframe con una fila por partido, o NULL si no hay datos.
extraer_senado <- function(cod_municipio) {
    url   <- paste0("https://resultados.registraduria.gov.co/json/ACT/SE/", cod_municipio, ".json")
    datos <- get_json(url)
    
    # Validaciones defensivas: si falta cualquier nivel de la jerarquía,
    # retornamos NULL en lugar de explotar con un error críptico.
    if (is.null(datos) || is.null(datos$camaras) || length(datos$camaras) == 0) return(NULL)
    
    senado <- datos$camaras[[1]]  # tomamos el primer (y único) elemento: Senado
    if (is.null(senado$partotabla) || length(senado$partotabla) == 0) return(NULL)
    
    # Iteramos sobre cada partido en la lista y construimos un dataframe por partido.
    # lapply devuelve una lista de dataframes; bind_rows los apila en uno solo.
    lapply(senado$partotabla, function(p) {
        data.frame(
            cod_municipio = cod_municipio,
            cod_partido   = p$act$codpar %||% NA,
            votos         = as.numeric(p$act$vot  %||% 0),
            pct           = p$act$pvot  %||% NA,   # se limpia después con limpiar_pct()
            stringsAsFactors = FALSE
        )
    }) %>% bind_rows()
}


# extraer_participacion_senado: extrae métricas de participación electoral.
#
# ⚠️  Trampa del JSON: hay DOS niveles de totales y NO son lo mismo.
#
#   datos$totales$act              → totales GLOBALES (todas las circunscripciones)
#                                    Úsalos para: censo electoral y votantes totales.
#                                    Esto es lo que muestra la BARRA SUPERIOR del sitio.
#
#   datos$camaras[[1]]$totales$act → totales de circunscripción NACIONAL/TERRITORIAL
#                                    Úsalos para: nulos, no marcados, válidos, blanco.
#                                    Esto es lo que muestra el PIE DE PÁGINA del sitio.
#
# Si mezclas los dos niveles, tus porcentajes de participación quedan mal.
# Aquí se mezcla intencionalmente para replicar exactamente lo que muestra la web.
extraer_participacion_senado <- function(cod_municipio) {
    url   <- paste0("https://resultados.registraduria.gov.co/json/ACT/SE/", cod_municipio, ".json")
    datos <- get_json(url)
    
    if (is.null(datos) || is.null(datos$camaras) || length(datos$camaras) == 0) return(NULL)
    
    t_total <- datos$totales$act                   # nivel raíz: para censo y votantes totales
    t       <- datos$camaras[[1]]$totales$act      # nivel territorial: para calidad del voto
    if (is.null(t)) return(NULL)
    
    data.frame(
        cod_municipio      = cod_municipio,
        # ── Del nivel raíz (todas las circunscripciones) ──────────────────
        censo              = as.numeric(t_total$centota  %||% NA),   # personas habilitadas para votar
        votantes_total     = as.numeric(t_total$votant   %||% NA),   # personas que efectivamente votaron
        pct_votantes_total = limpiar_pct(t_total$pvotant %||% NA),   # % de participación total
        # ── Del nivel territorial (circunscripción nacional) ──────────────
        votantes           = as.numeric(t$votant   %||% NA),         # votantes en circ. territorial
        pct_votantes       = limpiar_pct(t$pvotant  %||% NA),
        votos_nulos        = as.numeric(t$votnul   %||% NA),         # votos nulos (los rabiosos)
        pct_nulos          = limpiar_pct(t$pvotnul  %||% NA),
        votos_no_marcados  = as.numeric(t$votnma   %||% NA),         # tarjetas en blanco sin marcar nada
        pct_no_marcados    = limpiar_pct(t$pvotnma  %||% NA),
        votos_blanco       = as.numeric(t$votbla   %||% NA),         # voto en blanco intencional
        pct_blanco         = limpiar_pct(t$pvotbla  %||% NA),
        votos_validos      = as.numeric(t$votval   %||% NA),         # válidos = a partidos + blanco
        pct_validos        = limpiar_pct(t$pvotval  %||% NA),
        votos_a_partidos   = as.numeric(t$votcan   %||% NA),         # votos que realmente cuentan para curules
        pct_a_partidos     = limpiar_pct(t$pvotcan  %||% NA),
        stringsAsFactors   = FALSE
    )
}


# ============================================================
# 5. NOMENCLATOR DE MUNICIPIOS
#
# La Registraduría tiene un JSON maestro con todos los municipios
# y sus códigos. Lo descargamos una vez al inicio.
# Es como el directorio telefónico pero para el Estado colombiano.
#
# Estructura del JSON:
#   nom$amb[[1]]$ambitos → lista de entidades geográficas con niveles:
#     l == 1 : país
#     l == 2 : departamento
#     l == 3 : municipio  ← estos son los que nos importan
#
# Cada entidad tiene:
#   co : código (ej: "01001" para Medellín)
#   n  : nombre
#   l  : nivel geográfico
# ============================================================

nom_raw  <- GET(
    "https://resultados.registraduria.gov.co/json/nomenclator.json",
    add_headers(.headers = headers)
)
nom      <- fromJSON(rawToChar(nom_raw$content), simplifyVector = FALSE)
ambitos  <- nom[["amb"]][[1]][["ambitos"]]

# Nos quedamos solo con los municipios (nivel 3).
# Filter() es como dplyr::filter() pero para listas base de R.
municipios_nom <- Filter(function(x) x[["l"]] == 3, ambitos)

# Construimos el dataframe de municipios.
# substr(..., 1, 4) extrae los primeros 4 caracteres del código,
# que corresponden al código del departamento.
df_municipios <- data.frame(
    cod_municipio = sapply(municipios_nom, function(x) x[["co"]]),
    municipio     = sapply(municipios_nom, function(x) x[["n"]]),
    cod_depto     = substr(sapply(municipios_nom, function(x) x[["co"]]), 1, 4),
    stringsAsFactors = FALSE
)

# Diccionario manual de departamentos.
# Sí, es largo. No, no hay una API mejor para esto.
# Colombia tiene 32 departamentos + Bogotá D.C. + consulados en el exterior.
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

# sapply recorre cada código de depto y lo traduce a nombre.
# Si el código no está en el diccionario, devuelve el código mismo
# para no perder información (mejor dato raro que dato perdido).
df_municipios$departamento <- sapply(df_municipios$cod_depto, function(x) {
    nombre <- deptos_nombres[[x]]
    if (is.null(nombre)) x else nombre
})

cat("Municipios cargados:", nrow(df_municipios), "\n")
# Si ves ~1189 municipios, todo está bien. Si ves menos, algo falló arriba.


# ============================================================
# 6. LOOP DE SCRAPING
#
# El corazón del script. Recorre los ~1189 municipios uno a uno
# y extrae votos + participación de cada uno.
#
# Diseño del loop:
#   - Dos listas separadas (votos y participación) para acumular resultados.
#     Listas son más eficientes que ir haciendo bind_rows() en cada iteración.
#   - Vector 'errores' para registrar municipios que fallaron.
#   - Backup automático cada 200 municipios. Porque la luz se va, el internet
#     se corta, y el computador hace lo que quiere. El backup es tu seguro de vida.
#   - Sys.sleep(0.3): pausa de 0.3 segundos entre requests. Es cortesía básica
#     con el servidor. Sin esto eres ese invitado que llega y come todo el bufet.
#
# Tiempo estimado: ~1189 municipios × 0.3s = ~6 minutos.
# Ve por un café. El script no te necesita.
# ============================================================

df_votos_list <- list()   # acumula dataframes de votos por partido
df_part_list  <- list()   # acumula dataframes de participación
errores       <- c()      # guarda códigos de municipios que fallaron
total         <- nrow(df_municipios)

for (i in seq_len(total)) {
    cod   <- df_municipios$cod_municipio[i]
    muni  <- df_municipios$municipio[i]
    depto <- df_municipios$departamento[i]
    
    # Imprime progreso cada 50 municipios para saber que el script sigue vivo.
    # Silencio total en un loop largo es señal de que algo está mal (o de que terminó).
    if (i %% 50 == 0) cat(sprintf("[%d/%d] %s - %s\n", i, total, depto, muni))
    
    # ── Votos por partido ──────────────────────────────────────────────────
    # tryCatch extra por si extraer_senado() lanza un error no contemplado.
    # (el get_json() ya maneja errores HTTP, pero esto cubre casos raros)
    votos <- tryCatch(extraer_senado(cod), error = function(e) NULL)
    if (!is.null(votos) && nrow(votos) > 0) {
        df_votos_list[[cod]] <- votos   # guardamos con el código como nombre de elemento
    } else {
        errores <- c(errores, cod)      # registramos el fallo para inspección posterior
    }
    
    # ── Participación electoral ────────────────────────────────────────────
    part <- tryCatch(extraer_participacion_senado(cod), error = function(e) NULL)
    if (!is.null(part)) df_part_list[[cod]] <- part
    
    # ── Backup automático cada 200 municipios ─────────────────────────────
    # saveRDS guarda objetos R en formato binario comprimido.
    # Es más rápido y fiel que CSV para listas anidadas.
    # Ajusta la ruta si tu carpeta de descargas es diferente.
    if (i %% 200 == 0) {
        saveRDS(df_votos_list, "~/Downloads/elecciones 2026/backup_senado_votos.rds")
        saveRDS(df_part_list,  "~/Downloads/elecciones 2026/backup_senado_part.rds")
        cat("  💾 Backup guardado en iteración", i, "\n")
    }
    
    Sys.sleep(0.3)  # pausa de cortesía. El servidor también necesita respirar.
}

# bind_rows() apila todos los dataframes de la lista en uno solo.
# Es el momento en que todo el trabajo del loop se vuelve un dataframe bonito.
df_votos <- bind_rows(df_votos_list)
df_part  <- bind_rows(df_part_list)

cat("Municipios con votos:", length(df_votos_list), "\n")
cat("Municipios con participación:", length(df_part_list), "\n")
cat("Errores (municipios sin datos):", length(errores), "\n")
# Algunos municipios pueden no tener datos si la Registraduría no los reportó aún.
# Revisa 'errores' para ver cuáles son. Probablemente son municipios muy pequeños
# o circunscripciones especiales que usan un endpoint diferente.


# ============================================================
# 7. CONSTRUCCIÓN DEL DATAFRAME FINAL
#
# Unimos votos + municipios + participación en una sola tabla.
# Luego mapeamos códigos de partido a nombres legibles
# y los agrupamos en familias políticas para análisis estratégico.
#
# El case_when() es el switch/case de dplyr. Lee de arriba hacia abajo
# y asigna el primer caso que se cumple. El TRUE al final es el "default".
#
# Familias políticas: agrupación propia basada en comportamiento
# coalicional histórico. No es oficial, es analítica.
# ============================================================

df_senado_final <- df_votos %>%
    # left_join preserva todos los registros de df_votos aunque no haya match.
    # Aquí siempre debería haber match porque los códigos vienen del mismo nomenclator.
    left_join(df_municipios, by = "cod_municipio") %>%
    left_join(df_part,       by = "cod_municipio") %>%
    mutate(
        # ── Nombre del partido ────────────────────────────────────────────
        # Los códigos son asignados por la Registraduría y son consistentes
        # a nivel nacional para Senado. Para Cámara pueden variar por circunscripción.
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
            TRUE ~ paste0("PARTIDO_", cod_partido)  # código desconocido: lo nombramos con su código
        ),
        # ── Familia política ──────────────────────────────────────────────
        # Agrupación en bloques para análisis de coaliciones y comportamiento electoral.
        # Útil para agregar votos por tendencia en lugar de por partido individual.
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
# 8. GUARDAR OUTPUTS
#
# Dos formatos:
#   .rds  → para seguir trabajando en R (rápido, comprimido, fiel al tipo de datos)
#   .xlsx → para compartir con humanos que usan Excel (bienvenidos, no los juzgamos)
#
# El writexl::write_xlsx() acepta una lista nombrada de dataframes,
# donde cada elemento se convierte en una hoja del Excel.
# Aquí solo tenemos una hoja ("partidos"), pero la estructura permite
# agregar más fácilmente (ej: list(partidos = ..., participacion = ...)).
#
# Ajusta las rutas si guardas tus datos en otro lugar.
# ============================================================

saveRDS(df_senado_final, "~/Downloads/elecciones 2026/df_senado.rds")

writexl::write_xlsx(
    list(
        partidos = df_senado_final %>%
            # distinct() elimina duplicados. Puede haber filas repetidas si
            # el loop procesó algún municipio más de una vez (raro pero posible).
            distinct(cod_municipio, municipio, departamento,
                     cod_partido, partido, familia, votos, pct,
                     censo, votantes_total, pct_votantes_total,
                     votantes, pct_votantes, votos_validos, votos_nulos,
                     votos_no_marcados, votos_blanco, pct_blanco,
                     votos_a_partidos, pct_a_partidos)
    ),
    "~/Downloads/elecciones 2026/senado_2026.xlsx"
)

# Resumen final. Si los números se ven raros, algo salió mal arriba.
# ~1189 municipios × ~13 partidos = ~15,000 filas es lo esperado.
cat("Filas totales:", nrow(df_senado_final), "\n")
cat("Municipios únicos:", n_distinct(df_senado_final$cod_municipio), "\n")
cat("Partidos únicos:", n_distinct(df_senado_final$partido), "\n")
cat("Todo guardado en ~/Downloads/elecciones 2026/ ✓\n")
cat("Hora de hacer los gráficos bonitos. Te lo mereces.\n")
