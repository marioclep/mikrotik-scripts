# mikrotik-scripts

Scripts para MikroTik RouterOS (v6.49 y v7), **by MKE Solutions**.

Cada script está en su carpeta, con su propio README: qué hace, cómo instalarlo y cómo desinstalarlo.

## Scripts

| Script | Qué hace |
|---|---|
| [c2-botnet](c2-botnet/) | Bloquea los servidores de control (C2) de botnets IoT y de TVBox (Aisuru, Kimwolf y otras) y detecta qué equipos de tu red están infectados. Usa la telemetría de [botnet.cl](https://botnet.cl). |

## Antes de usar cualquier script

- Leé el README del script y el código antes de importarlo.
- Probalo primero en un equipo de laboratorio.
- Hacé un backup: `/system backup save` y `/export file=antes`.

## Licencia

[MIT](LICENSE). Podés usar, modificar y compartir estos scripts, manteniendo el aviso de autoría.

## Contacto

Mario Clep · MKE Solutions · [X](https://x.com/marioclep) · [LinkedIn](https://www.linkedin.com/in/marioclep/)
