# ============================================================
# SCRAPER CÁMARA DE REPRESENTANTES COLOMBIA 2026
# Fuente: Registraduría Nacional del Estado Civil
# https://resultados.registraduria.gov.co
#
# Descripción: Extrae resultados electorales de la Cámara de
# Representantes 2026 (circunscripción territorial departamental)
# municipio por municipio, incluyendo votos por candidato Y por
# partido. Sí, esta vez también hay candidatos. Bienvenidos a la
# Cámara, donde todo es más complicado que en el Senado.
#
# Diferencia clave con el scraper del Senado:
#   El Senado tiene circunscripción NACIONAL — todos votan por
#   los mismos partidos. La Cámara tiene circunscripción
#   DEPARTAMENTAL — cada departamento tiene sus propias listas,
#   sus propias coaliciones y sus propios códigos de partido.
#   Eso explica por qué el diccionario de partidos aquí tiene
#   más de 100 entradas. No es un error. Es Colombia.
#
# Output:
#   - df_camara.rds     : base de datos en formato R
#   - camara_2026.xlsx  : Excel con DOS pestañas:
#       * candidatos : una fila por candidato por municipio
#       * partidos   : una fila por partido por municipio
#                      (votos de lista, sin preferente)
#
# Autor: BiancaHLenis
# Fecha: Marzo 2026
#
# Nota legal: Este script consume la API pública de la
# Registraduría. No se almacenan credenciales personales.
# ============================================================


# ============================================================
# 1. LIBRERÍAS
# Sin estas librerías este script es solo texto con ilusiones.
#   - httr     : hace las peticiones HTTP (el cartero)
#   - jsonlite : convierte JSON en objetos R (el traductor)
#   - dplyr    : manipulación de datos (la navaja suiza)
#   - writexl  : exporta a Excel (para los que aún no usan R)
#   - stringr  : limpieza de strings (el Marie Kondo del texto)
# ============================================================

library(httr)
library(jsonlite)
library(dplyr)
library(writexl)
library(stringr)


# ============================================================
# 2. HELPERS
# Funciones pequeñas que evitan repetir código y dramas.
# ============================================================

# %||%: retorna 'a' si no es NULL, de lo contrario retorna 'b'.
# Uso: valor <- campo_del_json %||% NA
# Sin esto, un solo NULL en el JSON tumba todo el dataframe.
# Es el cinturón de seguridad del scraper.
`%||%` <- function(a, b) if (!is.null(a)) a else b

# limpiar_pct: convierte porcentajes colombianos a numérico.
# La Registraduría reporta "25,69%" con coma decimal.
# R espera punto decimal. Esta función negocia entre los dos.
limpiar_pct <- function(x) {
    as.numeric(str_replace_all(x, c("%" = "", "," = ".")))
}


# ============================================================
# 3. CONFIGURACIÓN HTTP
#
# El servidor de la Registraduría está protegido por Cloudflare.
# Para que nos atienda, necesitamos presentarnos como un
# navegador normal (User-Agent) y tener una cookie de sesión
# válida (cf_clearance).
#
# ⚠️  La cookie CADUCA periódicamente. Si el scraper devuelve
# NULL en todos los municipios, es hora de renovarla:
#   1. Abre Chrome → https://resultados.registraduria.gov.co
#   2. F12 → pestaña Network
#   3. Recarga la página → click en cualquier request .json
#   4. En los headers del request, copia el valor de "Cookie"
#   5. Pégalo abajo donde dice PEGAR_AQUI_LA_COOKIE
#
# ⚠️  Nunca subas tu cookie real a GitHub.
#     Reemplázala siempre con el placeholder antes de publicar.
# ============================================================

headers <- c(
    'User-Agent' = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    'Cookie'     = 'PEGAR_AQUI_LA_COOKIE'
)

# get_json: hace un GET a una URL y parsea el JSON.
# Si el servidor dice "no" (HTTP != 200) o hay cualquier error,
# retorna NULL en lugar de explotar con un mensaje críptico.
# Lección de vida: siempre maneja tus errores con gracia.
get_json <- function(url) {
    tryCatch({
        resp <- GET(url, add_headers(.headers = headers))
        if (status_code(resp) == 200) {
            fromJSON(rawToChar(resp$content), simplifyVector = FALSE)
        } else {
            NULL
        }
    }, error = function(e) NULL)
}


# ============================================================
# 4. FUNCIONES DE EXTRACCIÓN
#
# Dos funciones separadas: una para votos (por partido y
# candidato) y otra para participación electoral.
# Separadas porque el JSON tiene estructuras distintas para
# cada cosa, y mezclarlas sería una telenovela de errores.
# ============================================================

# extraer_camara: extrae votos por partido Y candidato para un municipio.
#
# URL patrón: /json/ACT/CA/{cod_municipio}.json
# Donde CA = Cámara, ACT = resultados actuales.
#
# Estructura relevante del JSON:
#   datos
#   └── camaras[[1]]           ← cámara legislativa
#       └── partotabla         ← lista de partidos
#           └── [[i]]
#               └── act
#                   ├── codpar      ← código del partido
#                   ├── vot         ← votos totales del partido
#                   ├── pvot        ← % votos del partido
#                   └── cantotabla  ← lista de candidatos del partido
#                       └── [[j]]
#                           ├── codcan  ← código del candidato
#                           ├── cedula  ← cédula del candidato
#                           ├── nomcan  ← nombre
#                           ├── apecan  ← apellido
#                           ├── vot     ← votos del candidato
#                           ├── pvot    ← % votos del candidato
#                           └── carg    ← "1" si ganó curul, "0" si no
#
# Nota: codcan == "0" significa voto por lista sin candidato preferente.
# Cuando un partido no tiene candidatos en cantotabla, se registra
# solo el voto de lista con codcan = NA.
#
# Retorna un dataframe con una fila por candidato por municipio,
# o una fila por partido si no hay candidatos individuales.
extraer_camara <- function(cod_municipio) {
    url <- paste0(
        "https://resultados.registraduria.gov.co/json/ACT/CA/",
        cod_municipio, ".json"
    )
    datos <- get_json(url)

    # Validaciones defensivas: si falta cualquier nivel, retornamos NULL.
    # Es mejor un NULL controlado que un error que tumbe el loop completo.
    if (is.null(datos) ||
        is.null(datos$camaras) ||
        length(datos$camaras) == 0) return(NULL)

    camara <- datos$camaras[[1]]
    if (is.null(camara$partotabla) ||
        length(camara$partotabla) == 0) return(NULL)

    # Iteramos sobre cada partido en la lista
    lapply(camara$partotabla, function(p) {
        codpar <- p$act$codpar %||% NA
        vot    <- as.numeric(p$act$vot %||% 0)
        pvot   <- p$act$pvot %||% NA
        cands  <- p$act$cantotabla  # lista de candidatos del partido

        # Si el partido no tiene candidatos individuales (lista cerrada),
        # creamos una fila solo con el voto de partido
        if (is.null(cands) || length(cands) == 0) {
            return(data.frame(
                cod_municipio  = cod_municipio,
                codpar         = codpar,
                vot_partido    = vot,
                pvot_partido   = pvot,
                codcan         = NA,       # sin candidato específico
                cedula         = NA,
                candidato      = NA,
                vot_candidato  = NA,
                pvot_candidato = NA,
                carg           = "0",      # sin curul ganada
                stringsAsFactors = FALSE
            ))
        }

        # Si hay candidatos, creamos una fila por cada uno.
        # paste(nombre, apellido) + str_trim() elimina espacios extra.
        lapply(cands, function(c) {
            data.frame(
                cod_municipio  = cod_municipio,
                codpar         = codpar,
                vot_partido    = vot,          # votos totales del partido (se repite en cada candidato)
                pvot_partido   = pvot,
                codcan         = c$codcan %||% NA,
                cedula         = c$cedula %||% NA,
                candidato      = paste(c$nomcan %||% "", c$apecan %||% "") %>% str_trim(),
                vot_candidato  = as.numeric(c$vot %||% 0),
                pvot_candidato = c$pvot %||% NA,
                carg           = c$carg %||% "0",  # "1" = ganó curul, "0" = no ganó
                stringsAsFactors = FALSE
            )
        }) %>% bind_rows()
    }) %>% bind_rows()
}


# extraer_participacion_camara: extrae métricas de participación electoral.
#
# ⚠️  Misma trampa que en el Senado: hay DOS niveles de totales.
#
#   datos$totales$act              → totales GLOBALES (todas las circunscripciones)
#                                    Úsalos para: censo y votantes totales.
#
#   datos$camaras[[1]]$totales$act → totales de circunscripción TERRITORIAL
#                                    Úsalos para: nulos, blancos, válidos, no marcados.
#
# Mezclar los dos niveles produce porcentajes incorrectos.
# Esta función los combina intencionalmente para replicar
# lo que muestra la interfaz oficial de la Registraduría.
extraer_participacion_camara <- function(cod_municipio) {
    url <- paste0(
        "https://resultados.registraduria.gov.co/json/ACT/CA/",
        cod_municipio, ".json"
    )
    datos <- get_json(url)

    if (is.null(datos) ||
        is.null(datos$camaras) ||
        length(datos$camaras) == 0) return(NULL)

    t_total <- datos$totales$act                   # nivel raíz: censo y votantes totales
    t       <- datos$camaras[[1]]$totales$act      # nivel territorial: calidad del voto
    if (is.null(t)) return(NULL)

    data.frame(
        cod_municipio      = cod_municipio,
        # ── Del nivel raíz ────────────────────────────────────────────────
        censo              = as.numeric(t_total$centota  %||% NA),   # personas habilitadas
        votantes_total     = as.numeric(t_total$votant   %||% NA),   # personas que votaron
        pct_votantes_total = limpiar_pct(t_total$pvotant %||% NA),   # % participación
        # ── Del nivel territorial ─────────────────────────────────────────
        votantes           = as.numeric(t$votant   %||% NA),
        pct_votantes       = limpiar_pct(t$pvotant  %||% NA),
        votos_nulos        = as.numeric(t$votnul   %||% NA),         # los indignados
        pct_nulos          = limpiar_pct(t$pvotnul  %||% NA),
        votos_no_marcados  = as.numeric(t$votnma   %||% NA),         # los indecisos
        pct_no_marcados    = limpiar_pct(t$pvotnma  %||% NA),
        votos_blanco       = as.numeric(t$votbla   %||% NA),         # voto en blanco intencional
        pct_blanco         = limpiar_pct(t$pvotbla  %||% NA),
        votos_validos      = as.numeric(t$votval   %||% NA),         # válidos = partidos + blanco
        pct_validos        = limpiar_pct(t$pvotval  %||% NA),
        votos_a_partidos   = as.numeric(t$votcan   %||% NA),         # los que cuentan para curules
        pct_a_partidos     = limpiar_pct(t$pvotcan  %||% NA),
        stringsAsFactors   = FALSE
    )
}


# ============================================================
# 5. NOMENCLATOR DE MUNICIPIOS
#
# Descargamos el directorio oficial de municipios desde la
# Registraduría. Es el mapa que le dice al scraper dónde ir.
# Sin esto, estaríamos adivinando códigos de municipio.
# Spoiler: no terminaría bien.
#
# Estructura del JSON:
#   nom$amb[[1]]$ambitos → lista de entidades geográficas
#     l == 1 : país
#     l == 2 : departamento
#     l == 3 : municipio  ← solo estos nos importan
# ============================================================

nom_raw <- GET(
    "https://resultados.registraduria.gov.co/json/nomenclator.json",
    add_headers(.headers = headers)
)
nom     <- fromJSON(rawToChar(nom_raw$content), simplifyVector = FALSE)
ambitos <- nom[["amb"]][[1]][["ambitos"]]

# Filter() es como dplyr::filter() pero para listas base de R.
# Nos quedamos solo con nivel 3 = municipios.
municipios_nom <- Filter(function(x) x[["l"]] == 3, ambitos)

# Construimos el dataframe de municipios.
# substr(..., 1, 4) extrae los primeros 4 caracteres del código,
# que corresponden al departamento.
df_municipios <- data.frame(
    cod_municipio = sapply(municipios_nom, function(x) x[["co"]]),
    municipio     = sapply(municipios_nom, function(x) x[["n"]]),
    cod_depto     = substr(sapply(municipios_nom, function(x) x[["co"]]), 1, 4),
    stringsAsFactors = FALSE
)

# Diccionario manual de departamentos.
# Colombia tiene 32 departamentos + Bogotá D.C. + consulados.
# Sí, es largo. No, no hay una API más cómoda para esto.
deptos_nombres <- list(
    "0100" = "ANTIOQUIA",           "0300" = "ATLANTICO",
    "1600" = "BOGOTA D.C.",         "0500" = "BOLIVAR",
    "0700" = "BOYACA",              "0900" = "CALDAS",
    "4400" = "CAQUETA",             "4600" = "CASANARE",
    "1100" = "CAUCA",               "1200" = "CESAR",
    "1700" = "CHOCO",               "1300" = "CORDOBA",
    "1500" = "CUNDINAMARCA",        "5000" = "GUAINIA",
    "5400" = "GUAVIARE",            "1900" = "HUILA",
    "4800" = "LA GUAJIRA",          "2100" = "MAGDALENA",
    "5200" = "META",                "2300" = "NARINO",
    "2500" = "NORTE DE SANTANDER",  "6400" = "PUTUMAYO",
    "2600" = "QUINDIO",             "2400" = "RISARALDA",
    "5600" = "SAN ANDRES",          "2700" = "SANTANDER",
    "2800" = "SUCRE",               "2900" = "TOLIMA",
    "3100" = "VALLE",               "6800" = "VAUPES",
    "7200" = "VICHADA",             "4000" = "ARAUCA",
    "6000" = "AMAZONAS",            "8800" = "CONSULADOS"
)

# sapply traduce cada código de depto a su nombre.
# Si el código no está en el diccionario, devuelve el código mismo.
df_municipios$departamento <- sapply(df_municipios$cod_depto, function(x) {
    nombre <- deptos_nombres[[x]]
    if (is.null(nombre)) x else nombre
})

cat("Municipios cargados:", nrow(df_municipios), "\n")
# ~1189 municipios = todo está bien. Menos = algo falló arriba.


# ============================================================
# 6. LOOP DE SCRAPING
#
# El corazón del script. Recorre los ~1,189 municipios uno a uno.
# Para cada municipio extrae:
#   (a) votos por partido y candidato
#   (b) datos de participación electoral
#
# Detalles del diseño:
#   - Listas separadas para acumular resultados (más eficiente
#     que hacer bind_rows() en cada iteración del loop)
#   - Backup automático cada 200 municipios porque la vida es
#     incierta y el internet colombiano también
#   - Sys.sleep(0.3): pausa de cortesía con el servidor
#     Sin esto eres ese invitado que llega, come todo y se va
#
# Tiempo estimado: ~1,189 × 0.3s ≈ 6 minutos.
# Ve por un tinto. El script no te necesita.
# ============================================================

df_camara_list <- list()   # acumula dataframes de votos por candidato/partido
df_part_list   <- list()   # acumula dataframes de participación
errores        <- c()      # guarda municipios que fallaron
total          <- nrow(df_municipios)

for (i in seq_len(total)) {
    cod   <- df_municipios$cod_municipio[i]
    muni  <- df_municipios$municipio[i]
    depto <- df_municipios$departamento[i]

    # Progreso cada 50 municipios. El silencio en un loop largo
    # es señal de que algo está mal. O de que terminó. Difícil saberlo.
    if (i %% 50 == 0) cat(sprintf("[%d/%d] %s - %s\n", i, total, depto, muni))

    # ── Votos por partido y candidato ──────────────────────────────────
    votos <- tryCatch(extraer_camara(cod), error = function(e) NULL)
    if (!is.null(votos) && nrow(votos) > 0) {
        # Agregamos municipio y departamento directamente en el loop
        # para no tener que hacer un join después (ya están en la fila)
        votos$municipio    <- muni
        votos$departamento <- depto
        df_camara_list[[cod]] <- votos
    } else {
        errores <- c(errores, cod)
    }

    # ── Participación electoral ────────────────────────────────────────
    part <- tryCatch(extraer_participacion_camara(cod), error = function(e) NULL)
    if (!is.null(part)) df_part_list[[cod]] <- part

    # ── Backup automático cada 200 municipios ──────────────────────────
    # saveRDS guarda en formato binario comprimido de R.
    # Más rápido y confiable que CSV para objetos complejos.
    if (i %% 200 == 0) {
        saveRDS(df_camara_list, "~/Downloads/elecciones 2026/backup_camara_votos.rds")
        saveRDS(df_part_list,   "~/Downloads/elecciones 2026/backup_camara_part.rds")
        cat("  💾 Backup guardado en iteración", i, "\n")
    }

    Sys.sleep(0.3)  # pausa de cortesía. El servidor también respira.
}

# bind_rows() apila todos los dataframes en uno.
# Aquí es donde el loop se convierte en datos reales.
df_camara_votos <- bind_rows(df_camara_list)
df_part_camara  <- bind_rows(df_part_list)

cat("Municipios con votos:", length(df_camara_list), "\n")
cat("Municipios con participación:", length(df_part_list), "\n")
cat("Errores (municipios sin datos):", length(errores), "\n")


# ============================================================
# 7. CONSOLIDAR: JOIN + DICCIONARIO DE PARTIDOS + FAMILIAS
#
# Aquí unimos los votos con la participación y mapeamos los
# códigos de partido a nombres legibles.
#
# ⚠️  ADVERTENCIA: el diccionario de la Cámara es MUCHO más
# largo que el del Senado. Esto es normal y esperado.
#
# ¿Por qué? Porque la Cámara tiene circunscripción departamental.
# Cada departamento puede tener sus propias coaliciones locales
# con códigos únicos que no existen en otros departamentos.
# Por ejemplo, "REVIVE CAQUETA 2.0" solo existe en Caquetá.
# "PR1MERO CORDOBA" (con el 1 en lugar de la I) solo en Córdoba.
# Colombia es creativa con los nombres de coalición.
#
# Los códigos >= 6000 corresponden a circunscripciones especiales
# (comunidades étnicas, minorías, colombianos en el exterior).
# ============================================================

df_camara_final <- df_camara_votos %>%
    # Unimos con participación por municipio.
    # Los municipios sin participación quedan con NAs (no se pierden).
    left_join(df_part_camara, by = "cod_municipio") %>%
    mutate(

        # ── Nombre del partido ────────────────────────────────────────
        # Los códigos bajos (1-20) son partidos nacionales estables.
        # Los códigos altos (20+) son coaliciones departamentales
        # que varían elección a elección. El TRUE al final captura
        # cualquier código no mapeado y lo nombra con su código.
        partido = case_when(
            codpar == "1"   ~ "PARTIDO LIBERAL COLOMBIANO",
            codpar == "2"   ~ "PARTIDO CONSERVADOR COLOMBIANO",
            codpar == "3"   ~ "PARTIDO CAMBIO RADICAL",
            codpar == "4"   ~ "PARTIDO ALIANZA VERDE",
            codpar == "5"   ~ "PARTIDO ALIANZA VERDE",
            codpar == "6"   ~ "PARTIDO ASI",
            codpar == "7"   ~ "PARTIDO MIRA",
            codpar == "8"   ~ "PARTIDO DE LA U",
            codpar == "9"   ~ "PARTIDO DE LA U",
            codpar == "10"  ~ "PARTIDO CENTRO DEMOCRATICO",
            codpar == "11"  ~ "MOVIMIENTO MAIS",
            codpar == "12"  ~ "PARTIDO COLOMBIA JUSTA LIBRES",
            codpar == "14"  ~ "PARTIDO COLOMBIA JUSTA LIBRES",
            codpar == "15"  ~ "PARTIDO DIGNIDAD Y COMPROMISO",
            codpar == "16"  ~ "PARTIDO NUEVO LIBERALISMO",
            codpar == "17"  ~ "MOVIMIENTO SALVACION NACIONAL",
            codpar == "19"  ~ "PARTIDO NUEVO LIBERALISMO",
            codpar == "20"  ~ "MOVIMIENTO SALVACION NACIONAL",
            codpar == "21"  ~ "PARTIDO OXIGENO",
            codpar == "22"  ~ "PARTIDO LIBERAL COLOMBIANO",
            codpar == "25"  ~ "PARTIDO ECOLOGISTA COLOMBIANO",
            codpar == "26"  ~ "PACTO HISTORICO",
            codpar == "32"  ~ "PACTO HISTORICO",
            codpar == "35"  ~ "LISTA DE OVIEDO BOGOTA",
            codpar == "38"  ~ "CREEMOS",
            codpar == "41"  ~ "CD-MIRA",
            codpar == "42"  ~ "REVIVE CAQUETA 2.0",
            codpar == "45"  ~ "PARTIDO DE LA U-MIRA-MSN-ADA",
            codpar == "46"  ~ "CD-MIRA",
            codpar == "48"  ~ "PARTIDO CAMBIO RADICAL",
            codpar == "50"  ~ "MIRA-DIGNIDAD Y COMPROMISO",
            codpar == "51"  ~ "MOVIMIENTO MAIS",
            codpar == "52"  ~ "AHORA COLOMBIA",
            codpar == "53"  ~ "LA VOZ DEL AMAZONAS",
            codpar == "54"  ~ "ALIANZA POR NARINO",
            codpar == "56"  ~ "PUTUMAYO NOS UNE",
            codpar == "58"  ~ "CD-MIRA",
            codpar == "59"  ~ "PR1MERO CORDOBA",           # sí, con el número 1
            codpar == "61"  ~ "AHORA COLOMBIA",
            codpar == "62"  ~ "AHORA COLOMBIA",
            codpar == "63"  ~ "AHORA COLOMBIA",
            codpar == "65"  ~ "AHORA COLOMBIA",
            codpar == "67"  ~ "SUMA",
            codpar == "68"  ~ "AHORA COLOMBIA",
            codpar == "69"  ~ "CD-NUEVO LIBERALISMO-MIRA",
            codpar == "70"  ~ "PARTIDO DE LA U-CAMBIO RADICAL",
            codpar == "71"  ~ "AVANCEMOS NARINO",
            codpar == "76"  ~ "NUESTRA FUERZA",
            codpar == "77"  ~ "CR-ASI-CJL",
            codpar == "78"  ~ "CR-LAU-MSN-OXI",
            codpar == "79"  ~ "CR-CJL-LIGA DE GOBERNANTES",
            codpar == "80"  ~ "COALICION LIBERAL-COLOMBIA RENACIENTE",
            codpar == "81"  ~ "PACTO HISTORICO",
            codpar == "82"  ~ "AHORA COLOMBIA",
            codpar == "83"  ~ "PACTO HISTORICO",
            codpar == "84"  ~ "PACTO HISTORICO",
            codpar == "85"  ~ "PACTO HISTORICO",
            codpar == "86"  ~ "PACTO HISTORICO",
            codpar == "87"  ~ "PACTO HISTORICO",
            codpar == "89"  ~ "PACTO HISTORICO",
            codpar == "90"  ~ "PACTO HISTORICO",
            codpar == "91"  ~ "PACTO HISTORICO",
            codpar == "93"  ~ "PACTO HISTORICO",
            codpar == "94"  ~ "CR-NUEVO LIBERALISMO",
            codpar == "95"  ~ "CIUDADANOS RENOVEMOS",
            codpar == "96"  ~ "PACTO HISTORICO",
            codpar == "97"  ~ "ALMA",
            codpar == "98"  ~ "PARTIDO DE LA U-MIRA",
            codpar == "99"  ~ "COALICION CAQUETA",
            codpar == "100" ~ "PACTO VERDE POR EL TOLIMA",
            codpar == "103" ~ "COALICION DEMOCRATICA AMPLIA PAZ",
            codpar == "104" ~ "PACTO HISTORICO",
            codpar == "106" ~ "CD-PARTIDO DE LA U",
            codpar == "107" ~ "SALVACION-ALMA-OXIGENO",
            codpar == "109" ~ "PACTO HISTORICO",
            codpar == "110" ~ "POR RISARALDA",
            codpar == "111" ~ "ESPERANZA CHOCO",
            codpar == "112" ~ "PACTO HISTORICO",
            codpar == "113" ~ "PACTO HISTORICO",
            codpar == "114" ~ "ABC ALIANZA BOGOTA CONVERGENTE",
            codpar == "115" ~ "PACTO HISTORICO",
            codpar == "117" ~ "PACTO HISTORICO",
            codpar == "118" ~ "PARTIDO DE LA U-EN MARCHA",
            codpar == "119" ~ "PARTIDO ALIANZA VERDE",
            codpar == "120" ~ "PARTIDO DE LA U-MIRA",
            codpar == "121" ~ "CONSERVADOR-MSN",
            codpar == "122" ~ "CR-NUEVO LIBERALISMO",
            codpar == "123" ~ "BOGOTA ENTRE TODOS",
            codpar == "124" ~ "PACTO HISTORICO",
            codpar == "125" ~ "CD-PARTIDO CONSERVADOR",
            codpar == "127" ~ "PACTO HISTORICO",
            codpar == "128" ~ "FRENTE AMPLIO DEL CESAR",
            codpar == "129" ~ "ALMA CASANARE",
            codpar == "130" ~ "PACTO HISTORICO",
            codpar == "131" ~ "PUTUMAYO TAMBIEN ES COLOMBIA",
            codpar == "132" ~ "PARTIDO DE LA U-ECOLOGISTA",
            codpar == "137" ~ "ALMA-OXIGENO",
            codpar == "139" ~ "FUERZA POR EL HUILA",
            codpar == "141" ~ "FRENTE AMPLIO UNITARIO",
            codpar == "142" ~ "PACTO HISTORICO",
            codpar == "143" ~ "FRENTE AMPLIO UNITARIO",
            codpar == "146" ~ "FRENTE AMPLIO UNITARIO",
            codpar == "147" ~ "ALIANZA POR CASANARE",
            codpar == "149" ~ "MOTOCICLISTAS UNIDOS",
            codpar == "151" ~ "FRENTE AMPLIO RISARALDA",
            codpar == "152" ~ "AVANZA",
            codpar == "153" ~ "VERDE EN MARCHA",
            codpar == "154" ~ "COALICION ALIANZA VERDE BOLIVAR",
            codpar == "155" ~ "FRENTE AMPLIO DEL CESAR",
            codpar == "156" ~ "COALICION VERDE-EN MARCHA-LA FUERZA",
            codpar == "157" ~ "PACTO HISTORICO",
            codpar == "158" ~ "ALMA",
            codpar == "159" ~ "FRENTE AMPLIO UNITARIO",
            codpar == "160" ~ "COALICION FUERZA CIUDADANA",
            codpar == "161" ~ "COALICION FUERZA CIUDADANA",
            codpar == "163" ~ "COALICION ALIANZA CORDOBA",
            codpar == "164" ~ "PARTIDO ALIANZA VERDE",
            codpar == "165" ~ "COALICION FUERZA CIUDADANA",
            codpar == "166" ~ "COALICION FUERZA CIUDADANA",
            as.numeric(codpar) >= 6000 ~ "CIRCUNSCRIPCION ESPECIAL",  # comunidades étnicas y minorías
            TRUE ~ paste0("COALICION_", codpar)  # código no mapeado: lo nombramos con su código
        ),

        # ── Familia política ──────────────────────────────────────────
        # Agrupación en bloques para análisis de coaliciones.
        # La Cámara tiene muchas más coaliciones locales que el Senado,
        # pero la lógica de familias es la misma.
        # Esta clasificación es ANALÍTICA, no oficial.
        familia = case_when(
            partido %in% c("PARTIDO CENTRO DEMOCRATICO", "CD-MIRA",
                           "CD-NUEVO LIBERALISMO-MIRA", "CD-PARTIDO DE LA U",
                           "CD-PARTIDO CONSERVADOR")              ~ "GRAN CONSULTA CD",
            partido %in% c("PARTIDO LIBERAL COLOMBIANO",
                           "PARTIDO CONSERVADOR COLOMBIANO",
                           "PARTIDO CAMBIO RADICAL",
                           "PARTIDO DE LA U", "AHORA COLOMBIA",
                           "CREEMOS", "CR-LAU-MSN-OXI",
                           "COALICION LIBERAL-COLOMBIA RENACIENTE",
                           "BOGOTA ENTRE TODOS",
                           "CR-CJL-LIGA DE GOBERNANTES",
                           "CR-NUEVO LIBERALISMO", "CONSERVADOR-MSN",
                           "PARTIDO DE LA U-MIRA",
                           "PARTIDO DE LA U-MIRA-MSN-ADA",
                           "CR-ASI-CJL",
                           "PARTIDO DE LA U-CAMBIO RADICAL",
                           "PARTIDO DE LA U-EN MARCHA",
                           "PARTIDO DE LA U-ECOLOGISTA",
                           "SALVACION-ALMA-OXIGENO", "SUMA",
                           "LISTA DE OVIEDO BOGOTA",
                           "PARTIDO COLOMBIA JUSTA LIBRES",
                           "REVIVE CAQUETA 2.0")                  ~ "GRAN CONSULTA POTENCIAL",
            partido %in% c("PACTO HISTORICO", "PR1MERO CORDOBA",
                           "PACTO VERDE POR EL TOLIMA",
                           "COALICION DEMOCRATICA AMPLIA PAZ",
                           "AVANCEMOS NARINO", "ALIANZA POR NARINO",
                           "FRENTE AMPLIO UNITARIO")              ~ "PACTO HISTORICO",
            partido %in% c("PARTIDO ALIANZA VERDE",
                           "MOVIMIENTO SALVACION NACIONAL",
                           "PARTIDO NUEVO LIBERALISMO",
                           "VERDE EN MARCHA", "PARTIDO MIRA",
                           "PARTIDO OXIGENO", "AVANZA",
                           "CIUDADANOS RENOVEMOS", "NUESTRA FUERZA",
                           "ALMA-OXIGENO", "POR RISARALDA",
                           "COALICION VERDE-EN MARCHA-LA FUERZA",
                           "FRENTE AMPLIO RISARALDA",
                           "PARTIDO DIGNIDAD Y COMPROMISO",
                           "MIRA-DIGNIDAD Y COMPROMISO")          ~ "CENTRO INDEPENDIENTE",
            partido %in% c("CIRCUNSCRIPCION ESPECIAL",
                           "MOVIMIENTO MAIS")                     ~ "CIRCUNSCRIPCION ESPECIAL",
            TRUE ~ "OTRO"
        )
    )


# ============================================================
# 8. GUARDAR OUTPUTS
#
# Dos formatos, dos audiencias:
#   .rds  → para seguir trabajando en R (rápido, comprimido)
#   .xlsx → para compartir con el mundo Excel-dependiente
#
# El Excel tiene DOS pestañas:
#   * candidatos : tabla completa con una fila por candidato
#                  (útil para análisis de voto preferente)
#   * partidos   : solo votos de lista (codcan == "0")
#                  (útil para análisis agregado por partido)
#
# filter(codcan == "0") filtra solo los votos de lista sin
# candidato preferente, que es el voto "al partido" puro.
# ============================================================

saveRDS(df_camara_final, "~/Downloads/elecciones 2026/df_camara.rds")

writexl::write_xlsx(
    list(
        candidatos = df_camara_final,   # tabla completa con candidatos
        partidos   = df_camara_final %>%
            filter(codcan == "0") %>%   # solo votos de lista pura
            distinct(cod_municipio, municipio, departamento,
                     codpar, partido, familia, vot_partido, pvot_partido,
                     censo, votantes_total, pct_votantes_total,
                     votantes, pct_votantes, votos_validos, votos_nulos,
                     votos_no_marcados, votos_blanco, pct_blanco,
                     votos_a_partidos, pct_a_partidos)
    ),
    "~/Downloads/elecciones 2026/camara_2026.xlsx"
)

# Resumen final. Para la Cámara espera más filas que el Senado
# porque hay una fila por candidato, no solo por partido.
cat("Filas totales:", nrow(df_camara_final), "\n")
cat("Municipios únicos:", n_distinct(df_camara_final$cod_municipio), "\n")
cat("Partidos/coaliciones únicos:", n_distinct(df_camara_final$partido), "\n")
cat("Todo guardado en ~/Downloads/elecciones 2026/ ✓\n")
cat("La Cámara está en la base de datos. Colombia tiene representantes.\n")
