# Pausa — design system

Versión navegable, con vistas previas: https://claude.ai/artifact/JuEpHbixSfxCnGtg8xgV9C

Los tokens están en `tokens.json` y en Swift en `Design.swift`. Las guías de cada componente, en `components/`.

Pausa es una app de barra de menú para macOS que corta el trabajo para descansar la vista y el cuerpo. Su diseño tiene que ser como una buena pausa: callado, preciso y fácil de obedecer. La app casi nunca está a la vista. Cuando aparece, es una sola instrucción clara y un número que baja.

## Principios

- **Una cosa por pantalla.** La pausa muestra una instrucción, un tiempo y como mucho dos botones. Nada de decoración.
- **Nativo primero.** Menú, Configuración y controles son de macOS y siguen al sistema (tema, acento, tamaño de texto). La identidad propia vive en la pantalla de pausa, los banners y la barra de menú.
- **El estado se dice con forma y palabra, no solo con color.** Todo estado tiene su SF Symbol y su texto. `amber` y `danger` nunca van solos.
- **Lo grande es el tiempo.** El único elemento grande de toda la app es `rest-timer`. Si algo compite con él, sobra.

## Voz y textos

- Español rioplatense, de vos, en imperativo: "Mirá algo lejos", "Levantate", "Caminá, estirate, tomá agua".
- Frases cortas, sin signos de exclamación y sin punto final en títulos y botones. El subtítulo sí lleva punto si tiene dos frases.
- **Sin emoji en ningún lado**: ni en títulos, ni en el menú, ni en la barra. Los reemplazan los SF Symbols.
- Mayúscula solo al principio: "Pausa corta", "Crear una jam".
- Tiempos en formato `m:ss` ("4:12", "0:14"); duraciones con unidad corta ("20 s", "5 min"); en la cuenta del aviso previo, el número solo ("Pausa corta en 3").
- "…" solo en lo que está en curso ("Entrando a la jam…") o en ítems que abren una ventana ("Configuración…").
- Los errores dicen qué pasó y qué hacer: "No se pudo entrar a la jam. Prendé Pausa en Ajustes › Privacidad › Red local."
- Vocabulario fijo: *pausa corta* (vista), *pausa larga* (pararse), *posponer*, *saltar*, *jam* ("Crear una jam", "Unirme a una jam", "Terminar la jam", "Salir de la jam"), *Esperar a Claude*.

| Antes | Ahora |
| --- | --- |
| 👀  Mirá algo lejos | Mirá algo lejos (eyebrow: PAUSA CORTA · 20 S) |
| 🧍  Pará. Levantate. | Levantate (eyebrow: PAUSA LARGA · 5 MIN) |
| ☕  Esperando a Claude… | Claude está trabajando (eyebrow: EN ESPERA) |
| ⏸  Pausa pospuesta, activala apenas puedas · vuelve en 4:12 | Pausa pospuesta · vuelve en 4:12 |
| 👀  Pausa corta en 3 | Pausa corta en 3 |
| ⚠️ Revisá config.yml | Revisá config.yml (ícono `exclamationmark.triangle`) |
| 📞 después | `phone` + después |

## Color

- Una sola tinta de marca: `accent` (eucalipto). Botón principal, switches prendidos, progreso y foco. No la uses para texto largo ni para fondos grandes.
- Superficies: `ground` de fondo, `surface` para grupos, menús y banners, `line` para hairlines, `line-strong` para bordes de controles.
- Texto: `ink` principal, `ink-muted` secundario. Sobre un relleno `accent`, `on-accent` (en oscuro es tinta oscura, no blanco).
- Estados: `amber` para pospuesta o pendiente, `danger` para errores. Siempre con ícono y palabra.
- La pantalla de pausa usa su propio juego `rest-*`, igual en tema claro y oscuro: `rest-ground` a `rest-opacity`, `rest-ink` para título y tiempo, `rest-muted` para eyebrow y subtítulo, `rest-accent` para el progreso y el botón principal, `rest-raised` y `rest-line` para el secundario.
- Todo texto cumple 4.5:1 sobre los fondos que nombra su nota, en los dos temas. Bordes de control y foco, 3:1 o más.

## Tipografía

- Una familia: SF Pro, la del sistema. `display` (SF Pro Display) para la pantalla de pausa, `sans` (SF Pro Text) para el resto, `mono` (SF Mono) solo para config.yml y atajos si hiciera falta. En la app: `NSFont.systemFont` y `NSFont.monospacedDigitSystemFont`; no se embeben archivos de fuente.
- `rest-timer` es ultraliviano (200) y enorme. `rest-title` es semibold (600). El contraste de peso es el carácter de la marca: no los iguales.
- Todo número que cambia (tiempo, cuenta, contador) va con cifras tabulares.
- `eyebrow` es el único texto en mayúsculas, con 0.08em de espaciado.

## Espacio, forma y profundidad

- Escala de 4px: `space-1` a `space-16`. La pantalla de pausa usa los saltos grandes (`space-12`, `space-16`) para que respire. Menús y formularios, los chicos.
- Radios: `radius-sm` campos y chips, `radius-md` grupos y menús, `radius-lg` banners, `radius-pill` botones de la pausa y barra de progreso.
- Profundidad: solo `shadow-float`, y solo en lo que flota (banners, menús). Grupos de formulario con hairline `line`, sin sombra.
- Movimiento: la pausa aparece con un fundido de 400 ms y se va en 250 ms; el banner, 200 ms. Curva `cubic-bezier(.2, 0, 0, 1)`. Nada rebota ni se desliza. Con "Reducir movimiento", sin fundidos.

## Iconografía

- **SF Symbols**, peso regular, escala media, en modo plantilla. Son los íconos de la app en todas partes.
- Mapa fijo: `eye` pausa corta · `figure.walk` pausa larga · `moon.zzz` pospuesta · `phone` en reunión · `pause` pausado · `hourglass` esperando a Claude · `person.2` jam · `eye.slash` todo apagado · `exclamationmark.triangle` problema.
- En la barra de menú no se colorean (salvo `moon.zzz` en `amber`). En banners y menú, solo `amber` y `danger` tiñen íconos.
- Las vistas previas de este sistema usan dibujos lineales propios en lugar de SF Symbols, porque SF Symbols no se puede usar fuera de apps de Apple. En la app, usá siempre el símbolo real.
- La marca (`assets/Logos/pausa-mark.svg`): dos barras, la corta es la pausa de la vista y la larga la de pararse. Va en el ícono de la app y en Acerca de, nunca en la barra de menú.

## Componentes

- `BreakScreen`: la pantalla completa de cada pausa y de la espera de Claude.
- `Banner`: aviso previo, pospuesta y mensajes cortos, arriba al centro.
- `MenuBarItem`: ícono de estado y tiempo en la barra.
- `StatusMenu`: orden y textos del menú nativo.
- `Button`: píldoras de la pausa y los banners.
- `SettingsSection`: grupos de la ventana de Configuración.

Las vistas previas son HTML estático con `components/bundle.css` (clases `pa-*`). La app los implementa en AppKit y SwiftUI con estos mismos tokens.
