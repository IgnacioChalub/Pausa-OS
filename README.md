# Pausa

App de barra de menú para macOS que te recuerda descansar la vista y pararte.

- **Cada 20 min:** pantalla completa "👀 Mirá algo lejos" por 20 segundos.
- **Cada 1 hora:** pantalla completa "🧍 Pará. Levantate." por 5 minutos (se puede desactivar desde el menú).
- **Esc** cierra cualquier aviso.
- **En reuniones** (alguna app usando el micrófono) los avisos esperan a que cortes.
- **Cmd+Esc:** modo "Esperando a Claude", pantalla negra hasta que Claude Code termina de responder.
- Suena un "pop" cada vez que Claude Code termina de responder.

## Instalar

```sh
./build.sh
open ~/Applications/Pausa.app
```

Para que arranque sola: Configuración del Sistema → General → Ítems de inicio → agregar `Pausa.app`.

## Integración con Claude Code

Agregar en `~/.claude/settings.json`:

```json
"hooks": {
  "Stop": [
    { "hooks": [{ "type": "command", "command": "\"$HOME/Applications/Pausa.app/Contents/MacOS/Pausa\" --claude-done >/dev/null 2>&1 || true", "timeout": 5 }] }
  ],
  "Notification": [
    { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "\"$HOME/Applications/Pausa.app/Contents/MacOS/Pausa\" --claude-done >/dev/null 2>&1 || true", "timeout": 5 }] }
  ]
}
```

Los tiempos se cambian al principio de `main.swift`.
