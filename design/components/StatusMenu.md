# StatusMenu

El menú de Pausa: arriba el estado, después las acciones del momento, la jam y al final Configuración y Salir.

**Es un `NSMenu` nativo.** No se le cambia el fondo, la tipografía ni el resaltado: lo dibuja macOS. Este componente fija el orden, los textos y los íconos.

**Orden, separado en grupos por `separator`:**
1. Estado (ítems deshabilitados): la próxima pausa y cuánto falta, o el estado actual ("Pospuesta · vuelve en 4:59", "En reunión · la pausa espera"). Si hay jam, una línea con su estado. Si config.yml tiene errores, "Revisá config.yml" con submenú.
2. Acciones: Pausar / Reanudar (⌘P), Reiniciar contador (⌘R), Esperar a Claude (el atajo configurado).
3. Jam: "Crear una jam" y "Unirme a una jam ›" si estás solo; "Terminar la jam" si sos quien la creó; "Salir de la jam" si te uniste.
4. Configuración… (⌘,) y Salir de Pausa (⌘Q).

**Reglas:**
- Ítems de estado con su SF Symbol en `NSMenuItem.image` (plantilla), nunca un emoji al principio del título.
- Los ítems de estado no se eligen: deshabilitados, en el gris del sistema.
- Verbos en infinitivo para acciones ("Pausar", "Crear una jam"); "…" solo si abre otra ventana.
- Las pruebas de aviso ("Probar aviso de vista") van en Configuración, no en este menú.
