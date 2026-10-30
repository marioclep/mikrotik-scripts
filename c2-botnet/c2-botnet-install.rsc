# ==========================================================
#  C2 BOTNET v2 - instalador para RouterOS v6.49.x / v7
#  by MKE Solutions
#  Telemetria de C2: botnet.cl, de Rodrigo Pena
#  Importar con:  /import file-name=c2-botnet-install.rsc
#  Crea: script c2-botnet-update, scheduler cada 10 min
#        y reglas RAW DESHABILITADAS (hay que habilitarlas a mano).
#  Se puede reimportar: reemplaza lo instalado antes.
#
#  Cambios respecto de v1:
#  - Detecta si el servidor ignora el Range (hoy lo ignora) y no
#    repite la descarga: antes, con mas de ~32 KB de respuesta,
#    bajaba el JSON completo hasta 300 veces por corrida.
#  - Solo carga IP publicas sueltas (/32): descarta redes, privadas,
#    loopback, CGNAT, link-local y multicast.
#  - Tope de IP por corrida (maxEntries): si se pasa, no carga nada.
#  - Opcion check-certificate para validar el HTTPS.
#  - Evita dos corridas en paralelo.
#  - Mismo archivo para v6.49.x y v7: sin :foreach clave,valor,
#    direcciones pasadas a texto y renovacion con respaldo
#    (borrar y recrear) si no deja editar el vencimiento.
#  - Las reglas RAW se crean deshabilitadas, como dice el log.
#  - Regla opcional que anota en "C2 INFECTADOS" los equipos de
#    tu red que intentan hablar con un C2.
# ==========================================================

# --- Limpieza de una instalacion previa ---
/system scheduler remove [find name="c2-botnet-update"]
/system script remove [find name="c2-botnet-update"]
/ip firewall raw remove [find comment~"^C2 BOTNET"]

# --- Script ---
/system script
add name=c2-botnet-update policy=read,write,policy,test source="# ==========================================================\r\
    \n#  c2-botnet-update v2  -  RouterOS v6.49.x / v7\r\
    \n#  by MKE Solutions\r\
    \n#  Descarga las IP de C2 desde botnet.cl y las carga en la\r\
    \n#  address-list \"C2 BOTNET\". Pensado para correr cada 10 min.\r\
    \n#  Telemetria de C2: botnet.cl (Rodrigo Pena)\r\
    \n# ==========================================================\r\
    \n\r\
    \n# ----------------- CONFIGURACION -----------------\r\
    \n:local url \"https://botnet.cl/api/v2/c2\"\r\
    \n:local listName \"C2 BOTNET\"\r\
    \n# Tiempo de vida de cada entrada. Cada corrida la renueva;\r\
    \n# si una IP deja de aparecer en la API, se borra sola al vencer.\r\
    \n# Si la API no responde por mas de este tiempo, la lista queda vacia.\r\
    \n:local entryTimeout 35m\r\
    \n# Si la respuesta trae mas IP que esto, no se carga nada\r\
    \n# (proteccion ante una fuente rota o manipulada).\r\
    \n:local maxEntries 2000\r\
    \n# Verificacion del certificado HTTPS: no | yes | yes-without-crl\r\
    \n# Para usar \"yes\" hay que importar antes la CA raiz en /certificate.\r\
    \n:local checkCert \"no\"\r\
    \n# Tamano de bloque. Si el router rechaza bloques grandes,\r\
    \n# el script baja solo a 4000 bytes.\r\
    \n:local chunkSize 32000\r\
    \n:local maxChunks 300\r\
    \n# Filtro opcional para quedarse solo con objetos \"activos\", ej:\r\
    \n#   :local activeFilter \"\\\"status\\\":\\\"active\\\"\"\r\
    \n# Vacio = tomar todas las IP de la respuesta.\r\
    \n:local activeFilter \"\"\r\
    \n# Lista blanca: las IP cargadas en \"C2 WHITELIST\" nunca se bloquean.\r\
    \n# Ojo: compara la direccion exacta, no redes.\r\
    \n:local whiteList \"C2 WHITELIST\"\r\
    \n# --------------------------------------------------\r\
    \n\r\
    \n# No correr dos veces en paralelo\r\
    \n:if ([:len [/system script job find where script=\"c2-botnet-update\"]] > 1) do={\r\
    \n    :log warning \"C2 BOTNET: ya hay una actualizacion en curso, se omite\"\r\
    \n    :error \"c2-botnet-update en curso\"\r\
    \n}\r\
    \n\r\
    \n# Devuelve las IP publicas sueltas (/32) encontradas en un texto.\r\
    \n# Descarta redes, IP privadas, loopback, CGNAT, link-local y multicast.\r\
    \n:local recIPs do={\r\
    \n    :local out [:toarray \"\"]\r\
    \n    :local cands [:toarray \"\"]\r\
    \n    :local q1 [:find \$t \"\\\"\" -1]\r\
    \n    :if ([:typeof \$q1] = \"num\") do={\r\
    \n        # JSON: revisar solo los valores entre comillas\r\
    \n        :while ([:typeof \$q1] = \"num\") do={\r\
    \n            :local q2 [:find \$t \"\\\"\" \$q1]\r\
    \n            :if ([:typeof \$q2] = \"num\") do={\r\
    \n                :local seg [:pick \$t (\$q1 + 1) \$q2]\r\
    \n                :local l [:len \$seg]\r\
    \n                :if (\$l >= 7 && \$l <= 15) do={\r\
    \n                    :if ([:typeof [:find \"0123456789\" [:pick \$seg 0]]] = \"num\") do={\r\
    \n                        :set cands (\$cands , \$seg)\r\
    \n                    }\r\
    \n                }\r\
    \n                :set q1 [:find \$t \"\\\"\" \$q2]\r\
    \n            } else={\r\
    \n                :set q1 \"\"\r\
    \n            }\r\
    \n        }\r\
    \n    } else={\r\
    \n        # Texto plano: recorrido caracter por caracter (respaldo)\r\
    \n        :local s (\$t . \" \")\r\
    \n        :local tok \"\"\r\
    \n        :for i from=0 to=([:len \$s] - 1) do={\r\
    \n            :local c [:pick \$s \$i]\r\
    \n            :if ([:typeof [:find \"0123456789./\" \$c]] = \"num\") do={\r\
    \n                :set tok (\$tok . \$c)\r\
    \n            } else={\r\
    \n                :if ([:len \$tok] >= 7) do={ :set cands (\$cands , \$tok) }\r\
    \n                :set tok \"\"\r\
    \n            }\r\
    \n        }\r\
    \n    }\r\
    \n    # Validar candidatos\r\
    \n    :foreach s in=\$cands do={\r\
    \n        :if ([:typeof [:find \$s \"/\" -1]] != \"num\") do={\r\
    \n            :local d 0\r\
    \n            :local p [:find \$s \".\" -1]\r\
    \n            :while ([:typeof \$p] = \"num\") do={ :set d (\$d + 1); :set p [:find \$s \".\" \$p] }\r\
    \n            :if (\$d = 3 && [:typeof [:toip \$s]] = \"ip\") do={\r\
    \n                :local d1 [:find \$s \".\" -1]\r\
    \n                :local d2 [:find \$s \".\" \$d1]\r\
    \n                :local o1 [:tonum [:pick \$s 0 \$d1]]\r\
    \n                :local o2 [:tonum [:pick \$s (\$d1 + 1) \$d2]]\r\
    \n                :local bogon ((\$o1 = 0) || (\$o1 = 10) || (\$o1 = 127) || (\$o1 >= 224))\r\
    \n                :if (\$o1 = 100 && \$o2 >= 64 && \$o2 <= 127) do={ :set bogon true }\r\
    \n                :if (\$o1 = 169 && \$o2 = 254) do={ :set bogon true }\r\
    \n                :if (\$o1 = 172 && \$o2 >= 16 && \$o2 <= 31) do={ :set bogon true }\r\
    \n                :if (\$o1 = 192 && \$o2 = 168) do={ :set bogon true }\r\
    \n                :if (!\$bogon) do={ :set out (\$out , \$s) }\r\
    \n            }\r\
    \n        }\r\
    \n    }\r\
    \n    :return \$out\r\
    \n}\r\
    \n\r\
    \n# ---- Descargar y extraer las IP ----\r\
    \n:local delim \",\"\r\
    \n:if (\$activeFilter != \"\") do={ :set delim \"}\" }\r\
    \n\r\
    \n:local found [:toarray \"\"]\r\
    \n:local buffer \"\"\r\
    \n:local firstHead \"\"\r\
    \n:local offset 0\r\
    \n:local chunks 0\r\
    \n:local done false\r\
    \n:local failed false\r\
    \n\r\
    \n:while (!\$done) do={\r\
    \n    # ---- Descargar un bloque (con reintento a bloque chico) ----\r\
    \n    :local data \"\"\r\
    \n    :local ok false\r\
    \n    :local tries 0\r\
    \n    :while (!\$ok && \$tries < 2) do={\r\
    \n        :set tries (\$tries + 1)\r\
    \n        :do {\r\
    \n            :local res [/tool fetch url=\$url check-certificate=\$checkCert http-header-field=(\"Range: bytes=\" . \$offset . \"-\" . (\$offset + \$chunkSize - 1)) output=user as-value]\r\
    \n            :set data (\$res->\"data\")\r\
    \n            :set ok true\r\
    \n        } on-error={\r\
    \n            :if (\$chunks = 0 && \$chunkSize > 4000) do={\r\
    \n                :set chunkSize 4000\r\
    \n                :log info \"C2 BOTNET: bloque grande rechazado, usando 4000 bytes\"\r\
    \n            } else={\r\
    \n                :set tries 2\r\
    \n            }\r\
    \n        }\r\
    \n    }\r\
    \n\r\
    \n    :if (!\$ok) do={\r\
    \n        :if (\$chunks = 0) do={ :set failed true }\r\
    \n        :set done true\r\
    \n    } else={\r\
    \n        :if (\$chunks = 0) do={ :set firstHead [:pick \$data 0 40] }\r\
    \n        :if (\$chunks > 0 && [:pick \$data 0 40] = \$firstHead) do={\r\
    \n            # El servidor ignoro el Range y mando todo de nuevo:\r\
    \n            # lo que ya tenemos es la respuesta completa.\r\
    \n            :set done true\r\
    \n        } else={\r\
    \n            :set chunks (\$chunks + 1)\r\
    \n            :set offset (\$offset + \$chunkSize)\r\
    \n            :set buffer (\$buffer . \$data)\r\
    \n            # Bloque distinto al pedido = ultimo bloque, o el servidor\r\
    \n            # mando la respuesta entera de una (ignoro el Range).\r\
    \n            :if ([:len \$data] != \$chunkSize || \$chunks >= \$maxChunks) do={ :set done true }\r\
    \n        }\r\
    \n    }\r\
    \n\r\
    \n    # ---- Partir el buffer en registros completos ----\r\
    \n    :local start 0\r\
    \n    :local p [:find \$buffer \$delim -1]\r\
    \n    :while ([:typeof \$p] = \"num\") do={\r\
    \n        :local rec [:pick \$buffer \$start \$p]\r\
    \n        :if (\$activeFilter = \"\" || [:typeof [:find \$rec \$activeFilter -1]] = \"num\") do={\r\
    \n            :set found (\$found , [\$recIPs t=\$rec])\r\
    \n        }\r\
    \n        :set start (\$p + 1)\r\
    \n        :set p [:find \$buffer \$delim \$p]\r\
    \n    }\r\
    \n    :if (\$done) do={\r\
    \n        :local rec [:pick \$buffer \$start [:len \$buffer]]\r\
    \n        :if (\$activeFilter = \"\" || [:typeof [:find \$rec \$activeFilter -1]] = \"num\") do={\r\
    \n            :set found (\$found , [\$recIPs t=\$rec])\r\
    \n        }\r\
    \n        :set buffer \"\"\r\
    \n    } else={\r\
    \n        :set buffer [:pick \$buffer \$start [:len \$buffer]]\r\
    \n    }\r\
    \n}\r\
    \n\r\
    \n:if (\$failed) do={\r\
    \n    :log warning (\"C2 BOTNET: no se pudo descargar \" . \$url . \" (sin conexion, certificado o respuesta demasiado grande) - lista sin cambios\")\r\
    \n    :error \"descarga fallida\"\r\
    \n}\r\
    \n\r\
    \n# ---- Quitar duplicados y controlar el tope ----\r\
    \n# (lista simple + indice: :foreach clave,valor no es seguro en v6)\r\
    \n:local uniq [:toarray \"\"]\r\
    \n:local uniqList [:toarray \"\"]\r\
    \n:local total 0\r\
    \n:foreach a in=\$found do={\r\
    \n    :if ([:typeof (\$uniq->\$a)] != \"bool\") do={\r\
    \n        :set (\$uniq->\$a) true\r\
    \n        :set uniqList (\$uniqList , \$a)\r\
    \n        :set total (\$total + 1)\r\
    \n    }\r\
    \n}\r\
    \n:if (\$total = 0) do={\r\
    \n    :log warning \"C2 BOTNET: la respuesta no trajo IP validas - lista sin cambios\"\r\
    \n    :error \"sin IP\"\r\
    \n}\r\
    \n:if (\$total > \$maxEntries) do={\r\
    \n    :log warning (\"C2 BOTNET: la respuesta trajo \" . \$total . \" IP (tope \" . \$maxEntries . \") - no se carga nada\")\r\
    \n    :error \"demasiadas IP\"\r\
    \n}\r\
    \n\r\
    \n# ---- Indice de lo que ya esta en la lista (una sola pasada) ----\r\
    \n# :tostr porque v7 puede devolver la direccion como tipo ip y no texto\r\
    \n:local known [:toarray \"\"]\r\
    \n:foreach id in=[/ip firewall address-list find where list=\$listName] do={\r\
    \n    :set (\$known->[:tostr [/ip firewall address-list get \$id address]]) \$id\r\
    \n}\r\
    \n:foreach id in=[/ip firewall address-list find where list=\$whiteList] do={\r\
    \n    :set (\$known->[:tostr [/ip firewall address-list get \$id address]]) \"ok\"\r\
    \n}\r\
    \n\r\
    \n# ---- Cargar en la address-list ----\r\
    \n:local added 0\r\
    \n:local renewed 0\r\
    \n:foreach a in=\$uniqList do={\r\
    \n    :local k (\$known->\$a)\r\
    \n    :if ([:typeof \$k] = \"id\") do={\r\
    \n        # Renovar el vencimiento. Si la version no deja editar una\r\
    \n        # entrada dinamica, se borra y se vuelve a crear.\r\
    \n        :do {\r\
    \n            /ip firewall address-list set \$k timeout=\$entryTimeout\r\
    \n        } on-error={\r\
    \n            :do {\r\
    \n                /ip firewall address-list remove \$k\r\
    \n                /ip firewall address-list add list=\$listName address=\$a timeout=\$entryTimeout comment=\"botnet.cl C2 - by MKE Solutions\"\r\
    \n            } on-error={}\r\
    \n        }\r\
    \n        :set renewed (\$renewed + 1)\r\
    \n    } else={\r\
    \n        :if ([:typeof \$k] != \"str\") do={\r\
    \n            :do {\r\
    \n                /ip firewall address-list add list=\$listName address=\$a timeout=\$entryTimeout comment=\"botnet.cl C2 - by MKE Solutions\"\r\
    \n                :set added (\$added + 1)\r\
    \n            } on-error={}\r\
    \n        }\r\
    \n    }\r\
    \n}\r\
    \n\r\
    \n:log info (\"C2 BOTNET: \" . \$total . \" IP recibidas, \" . \$added . \" nuevas, \" . \$renewed . \" renovadas, \" . \$chunks . \" bloque(s)\")"

# --- Scheduler: cada 10 minutos ---
/system scheduler
add name=c2-botnet-update interval=10m on-event="/system script run c2-botnet-update" policy=read,write,policy,test comment="C2 BOTNET - actualiza la address-list - by MKE Solutions"

# --- Reglas RAW (DESHABILITADAS, al principio de raw y en este orden) ---
# 1. Anota en "C2 INFECTADOS" el equipo interno que intenta hablar con un C2 (no bloquea)
# 2. Bloquea el trafico hacia el C2
# 3. Bloquea el trafico que viene del C2
# 4. Bloquea al propio router hablando con un C2
:do {
    :local first ([/ip firewall raw find]->0)
    :if ([:typeof $first] = "id") do={
        /ip firewall raw add chain=prerouting dst-address-list="C2 BOTNET" action=add-src-to-address-list address-list="C2 INFECTADOS" address-list-timeout=1d disabled=yes comment="C2 BOTNET - detectar equipos infectados - by MKE Solutions" place-before=$first
        /ip firewall raw add chain=prerouting dst-address-list="C2 BOTNET" action=drop disabled=yes comment="C2 BOTNET - saliente hacia C2 - by MKE Solutions" place-before=$first
        /ip firewall raw add chain=prerouting src-address-list="C2 BOTNET" action=drop disabled=yes comment="C2 BOTNET - entrante desde C2 - by MKE Solutions" place-before=$first
        /ip firewall raw add chain=output dst-address-list="C2 BOTNET" action=drop disabled=yes comment="C2 BOTNET - router hacia C2 - by MKE Solutions" place-before=$first
    } else={
        /ip firewall raw add chain=prerouting dst-address-list="C2 BOTNET" action=add-src-to-address-list address-list="C2 INFECTADOS" address-list-timeout=1d disabled=yes comment="C2 BOTNET - detectar equipos infectados - by MKE Solutions"
        /ip firewall raw add chain=prerouting dst-address-list="C2 BOTNET" action=drop disabled=yes comment="C2 BOTNET - saliente hacia C2 - by MKE Solutions"
        /ip firewall raw add chain=prerouting src-address-list="C2 BOTNET" action=drop disabled=yes comment="C2 BOTNET - entrante desde C2 - by MKE Solutions"
        /ip firewall raw add chain=output dst-address-list="C2 BOTNET" action=drop disabled=yes comment="C2 BOTNET - router hacia C2 - by MKE Solutions"
    }
}

# --- Primera carga en segundo plano (no bloquea el import) ---
:execute script="/system script run c2-botnet-update"

:log info "C2 BOTNET (by MKE Solutions): instalacion completa. Las reglas quedaron DESHABILITADAS en /ip firewall raw: revisalas y habilitalas."
