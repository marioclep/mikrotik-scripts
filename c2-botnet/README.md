# C2 BOTNET para MikroTik (RouterOS v6.49 y v7)

**by [MKE Solutions](https://github.com/marioclep/mikrotik-scripts)**

Bloquea los servidores de control (C2) de botnets IoT y de TVBox (Aisuru, Kimwolf y otras) y detecta qué equipos de tu red intentan comunicarse con ellos.

La lista de C2 la publica [botnet.cl](https://botnet.cl/api/v2/c2), proyecto de Rodrigo Peña. Gracias por la telemetría.

## Qué hace

- Crea el script `c2-botnet-update` y un scheduler que lo corre cada 10 minutos.
- El script descarga la lista de C2 y la carga en la address-list `C2 BOTNET` con un vencimiento de 35 minutos. Si una IP deja de aparecer en la fuente, sale sola de la lista.
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

Se puede volver a importar cuando quieras: reemplaza lo instalado antes.

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
| `entryTimeout` | `35m` | Vencimiento de cada IP. Si la fuente no responde por más de este tiempo, la lista queda vacía. |
| `maxEntries` | `2000` | Tope de IP por corrida. Si se supera, no se carga nada. |
| `checkCert` | `no` | Validar el certificado HTTPS (`yes` o `yes-without-crl`). Requiere importar antes la CA raíz en `/certificate`. |

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
