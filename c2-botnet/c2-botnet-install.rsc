# ==========================================================
#  C2 BOTNET v3 - instalador para RouterOS v6.49.x / v7
#  by MKE Solutions
#  Telemetria de C2: botnet.cl, de Rodrigo Pena
#  Importar con:  /import file-name=c2-botnet-install.rsc
#  Crea: script c2-botnet-update, scheduler cada 1 hora
#        y reglas RAW DESHABILITADAS (hay que habilitarlas a mano).
#  Se puede reimportar sobre v1, v2 o v3 sin romper nada.
#
#  Cambios respecto de v2:
#  - RouterOS 6 lee como maximo 64512 bytes con output=user, y la
#    respuesta de botnet.cl ya es mas grande: se perdian las ultimas
#    IP. Ahora, si la respuesta llega cortada, se pide por familia
#    (parametro family=xxx). En v7, si entra completa, sigue siendo una
#    sola consulta.
#  - Avisa en el log si una familia falla, si una familia supera
#    64 KB o si llegan menos IP que las que informa el feed.
#  - Corre cada 1 hora en lugar de cada 10 min, y las entradas
#    vencen a las 3 horas en lugar de 35 min.
#  - Se quita la descarga por bloques (Range): el servidor la ignora.
#  - Al reimportar respeta las reglas RAW: si estan las 4, no las
#    toca (quedan habilitadas o no, como las dejaste). Si falta
#    alguna, las vuelve a crear al principio de raw y les devuelve
#    el estado que tenian.
#  - No borra la address-list: las IP ya cargadas y la lista
#    "C2 INFECTADOS" quedan como estaban.
# ==========================================================

# --- Limpieza de una instalacion previa (script y scheduler) ---
/system scheduler remove [find name="c2-botnet-update"]
/system script remove [find name="c2-botnet-update"]

# --- Script ---
/system script
add name=c2-botnet-update policy=read,write,policy,test source="# ==========================================================\r\
    \n#  c2-botnet-update v3  -  RouterOS v6.49.x / v7\r\
    \n#  by MKE Solutions\r\
    \n#  Descarga las IP de C2 desde botnet.cl y las carga en la\r\
    \n#  address-list \"C2 BOTNET\". Pensado para correr cada 1 hora.\r\
    \n#  Telemetria de C2: botnet.cl (Rodrigo Pena)\r\
    \n# ==========================================================\r\
    \n\r\
    \n# ----------------- CONFIGURACION -----------------\r\
    \n:local url \"https://botnet.cl/api/v2/c2\"\r\
    \n:local listName \"C2 BOTNET\"\r\
    \n# Tiempo de vida de cada entrada. Cada corrida la renueva;\r\
    \n# si una IP deja de aparecer en la API, se borra sola al vencer.\r\
    \n# Con 3h y una corrida por hora, la lista aguanta 2 fallas seguidas.\r\
    \n# Si la API no responde por mas de este tiempo, la lista queda vacia.\r\
    \n:local entryTimeout 3h\r\
    \n# Si la respuesta trae mas IP que esto, no se carga nada\r\
    \n# (proteccion ante una fuente rota o manipulada).\r\
    \n:local maxEntries 2000\r\
    \n# Tope de familias a consultar (misma proteccion).\r\
    \n:local maxFamilies 60\r\
    \n# Verificacion del certificado HTTPS: no | yes | yes-without-crl\r\
    \n# Para usar \"yes\" hay que importar antes la CA raiz en /certificate.\r\
    \n:local checkCert \"no\"\r\
    \n# RouterOS 6 lee como maximo 64512 bytes con output=user. Si la\r\
    \n# respuesta completa llega a ese tamano, se pide por familia.\r\
    \n:local userLimit 64512\r\
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
    \n# Devuelve los valores de \"clave\":\"valor\" encontrados en t,\r\
    \n# solo los que empiezan antes de la posicion hasta.\r\
    \n:local getVals do={\r\
    \n    :local out [:toarray \"\"]\r\
    \n    :local key (\"\\\"\" . \$k . \"\\\":\\\"\")\r\
    \n    :local kl [:len \$key]\r\
    \n    :local lim [:tonum \$hasta]\r\
    \n    :local p [:find \$t \$key -1]\r\
    \n    :while ([:typeof \$p] = \"num\") do={\r\
    \n        :if (\$p >= \$lim) do={\r\
    \n            :set p \"\"\r\
    \n        } else={\r\
    \n            :local s (\$p + \$kl)\r\
    \n            :local e [:find \$t \"\\\"\" \$s]\r\
    \n            :if ([:typeof \$e] = \"num\") do={\r\
    \n                :set out (\$out , [:pick \$t \$s \$e])\r\
    \n                :set p [:find \$t \$key \$e]\r\
    \n            } else={\r\
    \n                :set p \"\"\r\
    \n            }\r\
    \n        }\r\
    \n    }\r\
    \n    :return \$out\r\
    \n}\r\
    \n\r\
    \n# Valor numerico de \"count\":N (-1 si no esta)\r\
    \n:local getCount do={\r\
    \n    :local c [:find \$t \"\\\"count\\\":\" -1]\r\
    \n    :if ([:typeof \$c] != \"num\") do={ :return -1 }\r\
    \n    :local ce [:find \$t \",\" (\$c + 7)]\r\
    \n    :if ([:typeof \$ce] != \"num\") do={ :return -1 }\r\
    \n    :return [:tonum [:pick \$t (\$c + 8) \$ce]]\r\
    \n}\r\
    \n\r\
    \n# ---- 1) Descargar la respuesta completa ----\r\
    \n:local data \"\"\r\
    \n:do {\r\
    \n    :set data ([/tool fetch url=\$url check-certificate=\$checkCert output=user as-value]->\"data\")\r\
    \n} on-error={\r\
    \n    :log warning (\"C2 BOTNET: no se pudo descargar \" . \$url . \" (sin conexion o certificado) - lista sin cambios\")\r\
    \n    :error \"descarga fallida\"\r\
    \n}\r\
    \n:local feedTotal [\$getCount t=\$data]\r\
    \n:local ent [:find \$data \"\\\"entries\\\"\" -1]\r\
    \n:if ([:typeof \$ent] != \"num\") do={\r\
    \n    :log warning \"C2 BOTNET: formato inesperado (sin entries) - lista sin cambios\"\r\
    \n    :error \"formato\"\r\
    \n}\r\
    \n\r\
    \n:local found [:toarray \"\"]\r\
    \n:local mode \"completa\"\r\
    \n:local reqs 1\r\
    \n:local famErr \"\"\r\
    \n\r\
    \n# La respuesta llego entera si termina en \"]}\" y no quedo justo en\r\
    \n# el tope de RouterOS 6.\r\
    \n:local dl [:len \$data]\r\
    \n:local whole (\$dl != \$userLimit && \$dl >= 2 && [:pick \$data (\$dl - 2) \$dl] = \"]}\")\r\
    \n\r\
    \n:if (\$whole) do={\r\
    \n    # Entro completa: una sola consulta\r\
    \n    :set found [\$getVals t=\$data k=\"ip\" hasta=[:len \$data]]\r\
    \n} else={\r\
    \n    # ---- 2) Llego cortada (RouterOS 6): pedir por familia ----\r\
    \n    # La lista de familias esta al principio, antes de \"entries\".\r\
    \n    :set mode \"por familia\"\r\
    \n    :local families [\$getVals t=\$data k=\"id\" hasta=\$ent]\r\
    \n    :if ([:len \$families] = 0) do={\r\
    \n        :log warning \"C2 BOTNET: respuesta cortada y sin lista de familias - lista sin cambios\"\r\
    \n        :error \"sin familias\"\r\
    \n    }\r\
    \n    :if ([:len \$families] > \$maxFamilies) do={\r\
    \n        :log warning (\"C2 BOTNET: la respuesta trajo \" . [:len \$families] . \" familias (tope \" . \$maxFamilies . \") - lista sin cambios\")\r\
    \n        :error \"demasiadas familias\"\r\
    \n    }\r\
    \n    :local okChars \"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_\"\r\
    \n    :foreach f in=\$families do={\r\
    \n        # Solo nombres simples, para no armar URLs raras\r\
    \n        :local valid ([:len \$f] > 0 && [:len \$f] <= 40)\r\
    \n        :if (\$valid) do={\r\
    \n            :for i from=0 to=([:len \$f] - 1) do={\r\
    \n                :if ([:typeof [:find \$okChars [:pick \$f \$i]]] != \"num\") do={ :set valid false }\r\
    \n            }\r\
    \n        }\r\
    \n        :if (\$valid) do={\r\
    \n            :local fd \"\"\r\
    \n            :local ok true\r\
    \n            :do {\r\
    \n                :set fd ([/tool fetch url=(\$url . \"\\\?family=\" . \$f) check-certificate=\$checkCert output=user as-value]->\"data\")\r\
    \n            } on-error={ :set ok false }\r\
    \n            :set reqs (\$reqs + 1)\r\
    \n            :if (\$ok) do={\r\
    \n                :local fl [:len \$fd]\r\
    \n                :if (\$fl = \$userLimit || \$fl < 2 || [:pick \$fd (\$fl - 2) \$fl] != \"]}\") do={\r\
    \n                    :log warning (\"C2 BOTNET: la familia \" . \$f . \" llego cortada (supera 64 KB), se carga parcial\")\r\
    \n                }\r\
    \n                :set found (\$found , [\$getVals t=\$fd k=\"ip\" hasta=[:len \$fd]])\r\
    \n            } else={\r\
    \n                :set famErr (\$famErr . \" \" . \$f)\r\
    \n            }\r\
    \n        } else={\r\
    \n            :set famErr (\$famErr . \" (nombre invalido)\")\r\
    \n        }\r\
    \n    }\r\
    \n    :if ([:len \$famErr] > 0) do={\r\
    \n        :log warning (\"C2 BOTNET: fallaron las familias:\" . \$famErr)\r\
    \n    }\r\
    \n}\r\
    \n\r\
    \n# ---- 3) Validar, quitar duplicados e IP no publicas ----\r\
    \n# Solo IP sueltas (/32). Descarta redes, privadas, loopback,\r\
    \n# CGNAT, link-local y multicast.\r\
    \n# (lista simple + indice: :foreach clave,valor no es seguro en v6)\r\
    \n:local uniq [:toarray \"\"]\r\
    \n:local uniqList [:toarray \"\"]\r\
    \n:local total 0\r\
    \n:foreach s in=\$found do={\r\
    \n    :if ([:typeof (\$uniq->\$s)] != \"bool\") do={\r\
    \n        :set (\$uniq->\$s) true\r\
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
    \n                :if (!\$bogon) do={\r\
    \n                    :set uniqList (\$uniqList , \$s)\r\
    \n                    :set total (\$total + 1)\r\
    \n                }\r\
    \n            }\r\
    \n        }\r\
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
    \n:if (\$feedTotal > 0 && \$total < \$feedTotal) do={\r\
    \n    :log warning (\"C2 BOTNET: faltan IP (\" . \$total . \" de \" . \$feedTotal . \"), se cargan las recibidas\")\r\
    \n}\r\
    \n\r\
    \n# ---- 4) Indice de lo que ya esta en la lista (una sola pasada) ----\r\
    \n# :tostr porque v7 puede devolver la direccion como tipo ip y no texto\r\
    \n:local known [:toarray \"\"]\r\
    \n:foreach id in=[/ip firewall address-list find where list=\$listName] do={\r\
    \n    :set (\$known->[:tostr [/ip firewall address-list get \$id address]]) \$id\r\
    \n}\r\
    \n:foreach id in=[/ip firewall address-list find where list=\$whiteList] do={\r\
    \n    :set (\$known->[:tostr [/ip firewall address-list get \$id address]]) \"ok\"\r\
    \n}\r\
    \n\r\
    \n# ---- 5) Cargar en la address-list ----\r\
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
    \n:log info (\"C2 BOTNET: \" . \$total . \" IP de \" . \$feedTotal . \" en el feed, \" . \$added . \" nuevas, \" . \$renewed . \" renovadas, descarga \" . \$mode . \" (\" . \$reqs . \" consulta/s)\")"

# --- Scheduler: cada 1 hora ---
/system scheduler
add name=c2-botnet-update interval=1h on-event="/system script run c2-botnet-update" policy=read,write,policy,test comment="C2 BOTNET - actualiza la address-list - by MKE Solutions"

# --- Reglas RAW (DESHABILITADAS, al principio de raw y en este orden) ---
# 1. Anota en "C2 INFECTADOS" el equipo interno que intenta hablar con un C2 (no bloquea)
# 2. Bloquea el trafico hacia el C2
# 3. Bloquea el trafico que viene del C2
# 4. Bloquea al propio router hablando con un C2
# Si ya estan las 4 (instalacion previa), no se tocan.
:do {
    :local c1 "C2 BOTNET - detectar equipos infectados - by MKE Solutions"
    :local c2 "C2 BOTNET - saliente hacia C2 - by MKE Solutions"
    :local c3 "C2 BOTNET - entrante desde C2 - by MKE Solutions"
    :local c4 "C2 BOTNET - router hacia C2 - by MKE Solutions"
    :local n1 [:len [/ip firewall raw find where comment=$c1]]
    :local n2 [:len [/ip firewall raw find where comment=$c2]]
    :local n3 [:len [/ip firewall raw find where comment=$c3]]
    :local n4 [:len [/ip firewall raw find where comment=$c4]]
    :if ($n1 = 1 && $n2 = 1 && $n3 = 1 && $n4 = 1) do={
        :log info "C2 BOTNET: reglas RAW existentes, se mantienen como estaban"
    } else={
        # Guardar el estado de las que existan (las nuevas, deshabilitadas)
        :local s1 true
        :local s2 true
        :local s3 true
        :local s4 true
        :if ($n1 > 0) do={ :set s1 [/ip firewall raw get ([/ip firewall raw find where comment=$c1]->0) disabled] }
        :if ($n2 > 0) do={ :set s2 [/ip firewall raw get ([/ip firewall raw find where comment=$c2]->0) disabled] }
        :if ($n3 > 0) do={ :set s3 [/ip firewall raw get ([/ip firewall raw find where comment=$c3]->0) disabled] }
        :if ($n4 > 0) do={ :set s4 [/ip firewall raw get ([/ip firewall raw find where comment=$c4]->0) disabled] }
        /ip firewall raw remove [find where comment~"^C2 BOTNET"]
        :local first ([/ip firewall raw find]->0)
        :if ([:typeof $first] = "id") do={
            /ip firewall raw add chain=prerouting dst-address-list="C2 BOTNET" action=add-src-to-address-list address-list="C2 INFECTADOS" address-list-timeout=1d disabled=$s1 comment=$c1 place-before=$first
            /ip firewall raw add chain=prerouting dst-address-list="C2 BOTNET" action=drop disabled=$s2 comment=$c2 place-before=$first
            /ip firewall raw add chain=prerouting src-address-list="C2 BOTNET" action=drop disabled=$s3 comment=$c3 place-before=$first
            /ip firewall raw add chain=output dst-address-list="C2 BOTNET" action=drop disabled=$s4 comment=$c4 place-before=$first
        } else={
            /ip firewall raw add chain=prerouting dst-address-list="C2 BOTNET" action=add-src-to-address-list address-list="C2 INFECTADOS" address-list-timeout=1d disabled=$s1 comment=$c1
            /ip firewall raw add chain=prerouting dst-address-list="C2 BOTNET" action=drop disabled=$s2 comment=$c2
            /ip firewall raw add chain=prerouting src-address-list="C2 BOTNET" action=drop disabled=$s3 comment=$c3
            /ip firewall raw add chain=output dst-address-list="C2 BOTNET" action=drop disabled=$s4 comment=$c4
        }
        :log info "C2 BOTNET: reglas RAW creadas o reordenadas al principio de raw"
    }
}

# --- Primera carga en segundo plano (no bloquea el import) ---
:execute script="/system script run c2-botnet-update"

:log info "C2 BOTNET v3 (by MKE Solutions): instalacion completa. Revisa las reglas en /ip firewall raw: las nuevas quedan DESHABILITADAS."
