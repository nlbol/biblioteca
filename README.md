# Biblioteca - Núcleo Linux UAGRM

Biblioteca digital generada automáticamente con HTML5, CSS3 y JavaScript puro. Sin frameworks, sin backend, sin bases de datos.

## Características

- **100% Estático**: Todo el sitio se genera a partir de archivos JSON
- **Sin Backend**: No requiere PHP, Node.js, Python ni bases de datos
- **Responsive**: Se adapta a cualquier dispositivo (desktop, tablet, móvil)
- **Tema Oscuro**: Diseño profesional inspirado en terminales y hacking ético
- **Búsqueda en Tiempo Real**: Busca por título, categoría o etiquetas
- **Secciones Configurables**: Habilitar/deshabilitar secciones desde config.json
- **Accesible**: Cumple con estándares WCAG
- **PWA Ready**: Listo para Progressive Web App

## Requisitos

- Bash
- Python 3
- jq (procesador JSON)
- cp, mkdir, cat, sed (herramientas estándar de Unix)

## Instalación

```bash
# Clonar el repositorio
git clone https://github.com/nlbol/biblioteca.git
cd biblioteca

# Dar permisos de ejecución
chmod +x generador.sh

# Ejecutar el generador
./generador.sh
```

## Uso

```bash
# Modo producción (default)
./generador.sh

# Modo verbose (más detalles)
./generador.sh --verbose

# Modo desarrollo
./generador.sh --dev

# Mostrar ayuda
./generador.sh --help
```

## Estructura del Proyecto

```
biblioteca/
├── assets/                    # Archivos fuente (NUNCA editar public/)
│   ├── img/
│   │   └── covers/           # Portadas de libros (.webp)
│   ├── pdf/                   # Archivos PDF de libros
│   └── information/
│       ├── books.json        # Catálogo de libros
│       ├── config.json       # Configuración del sitio
│       ├── members.json      # Miembros del núcleo
│       ├── categories.json   # Categorías
│       ├── tags.json         # Etiquetas
│       └── about.json        # Contenido de la página Acerca de
├── scripts/                  # Scripts auxiliares
├── templates/                # Plantillas HTML
├── public/                   # Sitio generado (desechable)
├── generador.sh              # Script generador principal
└── README.md                 # Este archivo
```

## Reglas de Oro

1. **NUNCA editar `public/` directamente** - Siempre modificar `assets/`
2. **`public/` es desechable** - Se regenera completamente con `./generador.sh`
3. **Todo sale de `assets/`** - La información del sitio viene exclusivamente de ahí

## Agregar un Libro

1. Colocar el PDF en `assets/pdf/`
2. Colocar la portada (.webp) en `assets/img/covers/`
3. Agregar el registro en `assets/information/books.json`
4. Ejecutar `./generador.sh`

### Formato del JSON de libros

```json
{
    "title": "Título del Libro",
    "file": "nombre-archivo.pdf",
    "cover": "nombre-portada.webp",
    "pages": 240,
    "license": "CC-BY-SA",
    "category": "Categoría",
    "tags": ["tag1", "tag2", "tag3"],
    "year": 2024
}
```

El campo `file` solo requiere el nombre del archivo PDF. El generador busca automáticamente en `assets/pdf/` y genera los enlaces en `public/pdf/`.

## Secciones Configurables

Las secciones del sitio se pueden habilitar o deshabilitar desde `assets/information/config.json`:

```json
{
    "sections": {
        "home": true,
        "catalog": true,
        "about": true,
        "community": true
    }
}
```

Cuando una sección está en `false`:
- No aparece en el menú de navegación
- No se genera su página
- No se muestra ningún enlace hacia ella

## Configurar el Sitio

Editar `assets/information/config.json` para cambiar:

- **site.name**: Nombre del sitio
- **site.title**: Título principal
- **site.subtitle**: Subtítulo
- **site.description**: Descripción para SEO
- **site.domain**: Dominio del sitio
- **site.url**: URL completa del sitio
- **site.github**: URL del repositorio GitHub
- **site.email**: Correo de contacto (dejar vacío para ocultar)
- **colors**: Paleta de colores
- **footer.copyright**: Texto de copyright
- **buttons**: Textos de botones

Toda la información del sitio (footer, metadatos, enlaces) se obtiene centralizadamente desde `config.json`.

## Contenido de la Página Acerca de

El contenido de la sección "Acerca de" se define en `assets/information/about.json`:

```json
{
    "title": "Acerca de",
    "subtitle": "Biblioteca - Núcleo Linux UAGRM",
    "description": [
        "Primer párrafo...",
        "Segundo párrafo..."
    ],
    "mission": "Misión de la organización",
    "vision": "Visión de la organización",
    "objectives": [
        "Objetivo 1",
        "Objetivo 2"
    ]
}
```

## URLs

Las páginas se generan directamente en la raíz del sitio:

- `/` - Inicio
- `/catalog.html` - Catálogo
- `/about.html` - Acerca de
- `/community.html` - Comunidad
- `/pdf/nombre-libro.pdf` - Libros PDF

## Despliegue

El sitio generado en `public/` se puede desplegar en:

- **GitHub Pages**: Subir contenido de `public/` a la rama `gh-pages`
- **GitLab Pages**: Usar `.gitlab-ci.yml` con el generador
- **Cloudflare Pages**: Conectar repositorio y ejecutar `./generador.sh`
- **Apache/Nginx**: Copiar `public/` al directorio web

### Ejemplo con GitHub Pages

```bash
# Generar sitio
./generador.sh

# Entrar al directorio generado
cd public

# Inicializar git
git init
git add .
git commit -m "Deploy"

# Subir a GitHub
git remote add origin https://github.com/nlbol/biblioteca.git
git push -f origin main:gh-pages
```

## Tecnologías

- **HTML5**: Estructura semántica
- **CSS3**: Variables, Flexbox, Grid, Glassmorphism
- **JavaScript**: ES Modules, Fetch API
- **Bash**: Script de generación
- **Python 3**: Procesamiento de JSON

## Licencia

Este proyecto está licenciado bajo la **GNU General Public License v3.0**.

El contenido bibliográfico está licenciado bajo **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)**.

## Colaboradores

- Núcleo Linux UAGRM

## Enlaces

- [GitHub](https://github.com/nlbol)
- [Sitio Web](https://biblioteca.nluagrm.org)

---

Hecho con Software Libre por el **Núcleo Linux UAGRM**
