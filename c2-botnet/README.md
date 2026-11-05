# C2 BOTNET para MikroTik (RouterOS v6.49 y v7)

**by [MKE Solutions](https://github.com/marioclep/mikrotik-scripts)**

Bloquea los servidores de control (C2) de botnets IoT y de TVBox (Aisuru, Kimwolf y otras) y detecta qué equipos de tu red intentan comunicarse con ellos.

La lista de C2 la publica [botnet.cl](https://botnet.cl/api/v2/c2), proyecto de Rodrigo Peña. Gracias por la telemetría.

## Qué hace

- Crea el script `c2-botnet-update` y un scheduler que lo corre cada 1 hora.
- El script descarga la lista de C2 y la carga en la address-list `C2 BOTNET` con un vencimiento de 3 horas. Si una IP deja de aparecer en la fuente, sale sola de la lista.
- RouterOS v6 lee como máximo 63 KB por descarga y la lista de botnet.cl ya es más grande. Si la descarga llega cortada, el script pide la lista por familia de botnet (`?family=`) y la arma completa. En v7, si entra entera, hace una sola consulta.
- Avisa en el log si falta alguna IP, si falla alguna familia o si una familia llega cortada.
- Solo carga IP públicas sueltas: descarta redes, IP privadas, loopback, CGNAT, link-local y multicast.
- Si la respuesta trae más de 2000 IP, viene vacía o no se puede descargar, no toca la lista.
- Crea 4 reglas en `/ip firewall raw`, **todas deshabilitadas**:
  1. **Detectar**: anota en `C2 INFECTADOS`, durante 1 día, a cada equipo de tu red que intente conectarse a un C2. No bloquea.
  2. **Bloquear la salida**: corta lo que va de tu red hacia un C2.
  3. **Bloquear la entrada**: corta lo que llega desde un C2.
  4. **Bloquear al router**: corta las conexiones del propio router hacia un C2.

## Instalación

**Opción A: directo desde el router** (no hace falta bajar nada a la PC). En la terminal:

```
/tool fetch url="https://raw.githubusercontent.com/marioclep/mikrotik-scripts/main/c2-botnet/c2-botnet-install.rsc"
/import file-name=c2-botnet-install.rsc
```

**Opción B: subiendo el archivo.** Descargá [`c2-botnet-install.rsc`](c2-botnet-install.rsc), subilo al router (en WinBox: Files, arrastrar el archivo) y en la terminal:

```
/import file-name=c2-botnet-install.rsc
```

Después, verificá que haya cargado la lista:

```
/log print where message~"C2 BOTNET"
/ip firewall address-list print count-only where list="C2 BOTNET"
```

La línea del log dice cuántas IP cargó de las que tiene la lista (por ejemplo, `329 IP de 329 en el feed`) y si la descarga fue completa o por familia.

Se puede volver a importar cuando quieras: reemplaza el script y el scheduler, no borra las listas y no toca las reglas raw si ya están las 4 (si las habilitaste, siguen habilitadas).

## Uso recomendado

1. Habilitá **solo la regla de detección** ("C2 BOTNET - detectar equipos infectados").
2. Dejala unas horas y revisá:

```
/ip firewall address-list print where list="C2 INFECTADOS"
```

   Cada IP que aparezca es un equipo de tu red (casi siempre una TVBox) que intenta hablar con un C2.
3. Cuando estés conforme, habilitá las 3 reglas de bloqueo.

## Lista blanca

Las IP que cargues en la address-list `C2 WHITELIST` nunca se agregan a `C2 BOTNET`. Compara la dirección exacta, no redes.

## Configuración

Al principio del script `c2-botnet-update` (en `/system script`):

| Variable | Valor por defecto | Para qué sirve |
|---|---|---|
| `entryTimeout` | `3h` | Vencimiento de cada IP. Si la fuente no responde por más de este tiempo, la lista queda vacía. |
| `maxEntries` | `2000` | Tope de IP por corrida. Si se supera, no se carga nada. |
| `checkCert` | `no` | Validar el certificado HTTPS (`yes` o `yes-without-crl`). Requiere importar antes la CA raíz en `/certificate`. |

## Versiones

- **v3 (05/11/2026)**: en RouterOS v6 no se cargaban las últimas IP de la lista, porque la respuesta de botnet.cl ya pasa los 63 KB que v6 puede leer. Ahora, si llega cortada, se pide por familia. Corre cada 1 hora y las IP vencen a las 3 horas. Al reimportar, respeta el estado de las reglas raw. Si lo tenés instalado en v6, volvé a importarlo.
- **v2 (30/10/2026)**: primera versión publicada.

## Desinstalar

```
/system scheduler remove [find name="c2-botnet-update"]
/system script remove [find name="c2-botnet-update"]
/ip firewall raw remove [find comment~"^C2 BOTNET"]
/ip firewall address-list remove [find list="C2 BOTNET"]
```

## Aviso

Usalo bajo tu responsabilidad y probalo primero en un equipo de laboratorio. Las reglas se instalan deshabilitadas a propósito: revisalas antes de activarlas.

## Créditos

- Script: MKE Solutions (Mario Clep).
- Telemetría de C2: [botnet.cl](https://botnet.cl), de Rodrigo Peña.
