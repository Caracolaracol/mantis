# Sitio de Mantis

Sitio estático Astro de portada, documentación y licencia. Vive en este mismo repositorio, independiente de la app Swift.

- URL de producción: `https://caracolaracol.github.io/mantis/`.
- Node 22.23.4 o posterior; Astro fijado en `package.json` y lockfile.
- `npm run build` sincroniza captura e icono desde los recursos del repositorio.
- El caracol es el mismo recurso de la identidad personal usado en Raigambre.

## Desarrollo

```bash
cd website
npm ci
npm run dev
```

El paquete `node` de desarrollo mantiene un runtime local; los scripts de npm lo encuentran sin reemplazar el Node global. También puedes usar tu propio Node compatible y `.nvmrc`.

```bash
npm run build
npm test
npm run preview
```

Abre la ruta `/mantis/`, también durante el desarrollo. Los enlaces internos usan el prefijo de GitHub Pages.

## Grano en movimiento

Una textura SVG pequeña con `feTurbulence` se repite en una capa decorativa recortada al viewport. CSS mueve la capa en saltos mediante `transform` y `steps()`, sin recalcular el filtro sobre toda la pantalla en cada cuadro. El grano no captura clics ni se expone al lector de pantalla.

Se detiene con `prefers-reduced-motion`, puede pausarse desde el pie y deja de animarse al ocultar la pestaña. No requiere canvas, fuentes remotas, analítica ni servicios externos.

Referencias técnicas: [MDN: feTurbulence](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/feTurbulence) y [técnica de textura con saltos CSS](https://webdevpuneet.com/ui-snippets/noise-background/). Implementación propia bajo la licencia MIT del repositorio.

## Publicación

`.github/workflows/website.yml` compila y valida el sitio. En `main` publica `website/dist` usando GitHub Pages; los pull requests solo compilan y prueban. La web no compila, firma ni reemplaza Mantis ni el DMG.

El despliegue usa acciones fijadas a commits, lockfile y permisos de Pages limitados al job de publicación. Las vulnerabilidades moderadas, altas o críticas bloquean la compilación en CI. Al preparar el sitio quedó una alerta baja de esbuild relativa a su servidor de desarrollo en Windows; no se sirve un servidor de desarrollo en GitHub Pages. No se ejecutó `npm audit fix --force`.
