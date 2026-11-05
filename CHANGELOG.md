# Cambios

## 0.2.2 — 2026-11-05

Primera publicación de Mantis en GitHub.

### Incluye

- Grabación local de computador, entrada o aplicación; exportación de solo audio M4A.
- Biblioteca con búsqueda, reproducción, importación y arrastre nativo de archivos.
- Transcripción local opcional y catálogo de modelos con descargas confirmadas.
- Ajustes independientes, inicio en barra de menús e inicio de sesión opcional.
- Botón **Abrir en Finder** junto al listado de audios.
- **Privacidad → Restablecer permiso de audio…**, con confirmación, protección durante operaciones e instrucciones para volver a autorizar.

### Descarga e instalación

1. Descarga `Mantis-0.2.2.dmg` desde los archivos de esta Release.
2. Sal de Mantis si ya está abierta y arrastra la app a **Aplicaciones**.
3. Expulsa el DMG y abre la copia instalada.

Requiere **macOS 15+ y Apple Silicon**. El DMG incluye el motor, pero no pesos de modelos, grabaciones ni preferencias. El archivo `.sha256` permite verificar la integridad de la descarga.

### Avisos

- Firma local **ad hoc**, sin notarización de Apple. No desactives Gatekeeper globalmente.
- Cambiar de compilación puede exigir renovar permisos de macOS. El botón de recuperación solo restablece el permiso de pantalla/audio de Mantis; después hay que salir, abrir y aprobar el acceso nuevamente.
- La versión es experimental. No hay garantía de recuperación completa tras interrupciones ni de precisión de transcripción.
- 81 pruebas Swift y 7 pruebas Python pasan. La recepción en Gemini/NotebookLM, reuniones largas e inicio de sesión real aún requieren validación manual.
