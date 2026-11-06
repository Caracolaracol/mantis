# Cambios

## 0.3.0 — 2026-11-06

- App y sitio en inglés y español, con inglés predeterminado. Selector de idioma en bienvenida/General y EN/ES en todas las páginas del sitio.
- Catálogo compartido de traducciones y tablas nativas, incluidos mensajes, modelos, menús y permisos. Los títulos y textos del usuario se conservan sin traducir.
- Nuevo titular: “What you hear, Mantis records.” / “Lo que escuchas, Mantis lo graba.” Sin la frase superior ni la línea de subir grabaciones a una nube.
- Logo de cabeza de mantis sin recuadro, más grande; caracol del autor más pequeño.
- Brazo de mantis animado detrás del contenido, con ataque ocasional y silueta que se desvanece. Respeta pausa, movimiento reducido y pestañas ocultas.
- Capturas ficticias de la app en cada idioma y widget SketchyBar que sigue el idioma publicado por la app.
- 87 pruebas Swift, 12 Python y 7 del sitio; capturas nativas y seis páginas revisadas en móvil, tablet y escritorio.

La app mantiene firma ad hoc: actualizar puede requerir renovar la autorización de audio desde Settings → Privacy / Ajustes → Privacidad. No se restablecen permisos automáticamente.

- Sitio Astro en `website/`, publicado en GitHub Pages: portada, documentación, licencia y descarga del DMG.
- Paleta verde/rosa de Mantis, textura de grano animada con pausa y soporte de movimiento reducido, y caracol del autor enlazado a su portafolio.

- Widget reutilizable para SketchyBar en `integrations/sketchybar/mantis.sh`, con guía en README.
- Plugin configurable con detección de SketchyBar y ruta predeterminada de la app instalada.
- Pruebas de integración en dry-run; no requieren iniciar grabaciones ni modificar la barra.

## 0.2.2 — 2026-11-05

Primera publicación de Mantis en GitHub.

El código propio de Mantis está disponible bajo **licencia MIT**, con autoría de Agustin Rojas. Consulta el archivo `LICENSE`, también adjunto a la Release. Motor, dependencias y modelos conservan sus licencias independientes.

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
