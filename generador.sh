#!/usr/bin/env bash
#===============================================================================
# generador.sh - Generador de Sitio Estático
# Biblioteca - Núcleo Linux UAGRM
#
# Descripción:
#   Genera un sitio web estático completo a partir de archivos JSON, Markdown,
#   imágenes y PDFs almacenados en assets/. El sitio generado se coloca en
#   public/ y nunca debe editarse manualmente.
#
# Uso:
#   ./generador.sh                    # Modo producción (default)
#   ./generador.sh --verbose          # Modo verbose
#   ./generador.sh --dev              # Modo desarrollo
#   ./generador.sh --help             # Mostrar ayuda
#
#===============================================================================

set -euo pipefail

#===============================================================================
# CONFIGURACIÓN - Variables editables
#===============================================================================

# Nombre del sitio
SITE_NAME="Biblioteca"

# Directorios
ASSETS_DIR="assets"
PUBLIC_DIR="public"
SCRIPTS_DIR="scripts"
TEMPLATES_DIR="templates"

# Archivos JSON
BOOKS_JSON="${ASSETS_DIR}/information/books.json"
CONFIG_JSON="${ASSETS_DIR}/information/config.json"
MEMBERS_JSON="${ASSETS_DIR}/information/members.json"
CATEGORIES_JSON="${ASSETS_DIR}/information/categories.json"
TAGS_JSON="${ASSETS_DIR}/information/tags.json"
ABOUT_JSON="${ASSETS_DIR}/information/about.json"
THEMES_JSON="${ASSETS_DIR}/information/themes.json"

# Imágenes
COVERS_DIR="${ASSETS_DIR}/img/covers"

# PDFs
PDF_DIR="${ASSETS_DIR}/pdf"

# Modo de ejecución
VERBOSE=false

# Dominio para GitHub Pages (vacío = no generar CNAME)
CNAME_DOMAIN="biblioteca.nluagrm.org"
DEV_MODE=false

#===============================================================================
# COLORES - Para mensajes en terminal
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#===============================================================================
# FUNCIONES DE MENSAJES
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}[VERBOSE]${NC} $1"
    fi
}

#===============================================================================
# FUNCIONES DE UTILIDAD
#===============================================================================

# Mostrar ayuda
show_help() {
    cat << EOF
Uso: ./generador.sh [OPCIONES]

Genera un sitio web estático para la Biblioteca - Núcleo Linux UAGRM.

Opciones:
    --verbose, -v    Mostrar mensajes detallados de cada paso
    --dev, -d        Modo desarrollo (no optimiza archivos)
    --help, -h       Mostrar esta ayuda

Ejemplos:
    ./generador.sh                # Generar sitio en modo producción
    ./generador.sh --verbose      # Generar con mensajes detallados
    ./generador.sh --dev          # Generar en modo desarrollo

Directorios:
    assets/          → Archivos fuente (NUNCA editar public/ directamente)
    public/          → Sitio generado (desechable, se regenera完全)
    scripts/         → Scripts auxiliares
    templates/       → Plantillas HTML
EOF
}

# Verificar dependencias del sistema
check_dependencies() {
    log_info "Verificando dependencias..."
    
    local deps=("bash" "cp" "mkdir" "cat" "sed" "jq" "python3")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Dependencias faltantes: ${missing[*]}"
        log_error "Instale las dependencias requeridas."
        exit 1
    fi
    
    log_success "Todas las dependencias verificadas"
}

# Verificar soporte de conversión WEBP
check_webp_support() {
    log_info "Verificando soporte WEBP..."
    
    if command -v cwebp &> /dev/null; then
        log_success "cwebp encontrado."
        WEBP_AVAILABLE=true
        return 0
    fi
    
    log_warning "cwebp no encontrado."
    
    if command -v apt &> /dev/null; then
        log_info "Instalando soporte WEBP..."
        if apt-get update -qq > /dev/null 2>&1 && apt-get install -y -qq webp > /dev/null 2>&1; then
            if command -v cwebp &> /dev/null; then
                log_success "Conversión WEBP disponible."
                WEBP_AVAILABLE=true
                return 0
            fi
        fi
    fi
    
    log_warning "No se pudo instalar cwebp. Las imágenes se copiarán sin convertir."
    WEBP_AVAILABLE=false
    return 0
}

# Verificar que existan archivos requeridos
check_required_files() {
    log_info "Verificando archivos requeridos..."
    
    local files=("$BOOKS_JSON" "$CONFIG_JSON" "$MEMBERS_JSON" "$CATEGORIES_JSON" "$TAGS_JSON" "$ABOUT_JSON" "$THEMES_JSON")
    local missing=()
    
    for file in "${files[@]}"; do
        if [ ! -f "$file" ]; then
            missing+=("$file")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Archivos requeridos faltantes:"
        for file in "${missing[@]}"; do
            log_error "  - $file"
        done
        exit 1
    fi
    
    log_success "Todos los archivos requeridos encontrados"
}

# Leer valor de config.json
read_config() {
    local key="$1"
    python3 -c "
import json
with open('${CONFIG_JSON}', 'r') as f:
    config = json.load(f)
keys = '${key}'.split('.')
value = config
for k in keys:
    if isinstance(value, dict) and k in value:
        value = value[k]
    else:
        value = ''
        break
print(value if value is not None else '')
"
}

# Verificar si una sección está habilitada
is_section_enabled() {
    local section="$1"
    local result
    result=$(python3 -c "
import json
with open('${CONFIG_JSON}', 'r') as f:
    config = json.load(f)
sections = config.get('sections', {})
print('true' if sections.get('${section}', False) else 'false')
")
    [ "$result" = "true" ]
}

# Verificar si el sitio externo está habilitado
is_external_site_enabled() {
    local result
    result=$(python3 -c "
import json
with open('${CONFIG_JSON}', 'r') as f:
    config = json.load(f)
ext = config.get('externalSite', {})
enabled = ext.get('enabled', False)
print('true' if enabled else 'false')
")
    [ "$result" = "true" ]
}

# Leer valor del sitio externo
read_external_site() {
    local key="$1"
    python3 -c "
import json
with open('${CONFIG_JSON}', 'r') as f:
    config = json.load(f)
ext = config.get('externalSite', {})
value = ext.get('${key}', '')
if isinstance(value, bool):
    print('true' if value else 'false')
else:
    print(value if value is not None else '')
"
}

# Generar variables CSS del tema
generate_theme_css() {
    python3 -c "
import json

with open('${CONFIG_JSON}', 'r') as f:
    config = json.load(f)

theme_name = config.get('site', {}).get('theme', 'actual')

with open('${THEMES_JSON}', 'r') as f:
    themes = json.load(f)

theme = themes.get(theme_name, themes.get('actual', {}))
colors = theme.get('colors', {})

for key, value in colors.items():
    print(f'    --{key}: {value};')
"
}

#===============================================================================
# FUNCIONES DE LIMPIEZA
#===============================================================================

# Eliminar directorio public/ completo
clean_public() {
    log_info "Eliminando directorio public/..."
    
    if [ -d "$PUBLIC_DIR" ]; then
        rm -rf "$PUBLIC_DIR"
        log_success "Directorio public/ eliminado"
    else
        log_verbose "Directorio public/ no existe, creando..."
    fi
    
    mkdir -p "$PUBLIC_DIR"
    log_success "Directorio public/ creado"
}

#===============================================================================
# FUNCIONES DE GENERACIÓN
#===============================================================================

# Generar estructura de directorios en public/
create_structure() {
    log_info "Creando estructura de directorios..."
    
    mkdir -p "${PUBLIC_DIR}/css"
    mkdir -p "${PUBLIC_DIR}/js"
    mkdir -p "${PUBLIC_DIR}/img/covers"
    mkdir -p "${PUBLIC_DIR}/pdf"
    
    log_success "Estructura de directorios creada"
}

# Copiar archivos estáticos (imágenes, PDFs)
copy_static_assets() {
    log_info "Copiando archivos estáticos..."
    
    # Convertir y copiar portadas a WEBP
    if [ -d "$COVERS_DIR" ] && [ "$(ls -A "$COVERS_DIR" 2>/dev/null)" ]; then
        for src in "$COVERS_DIR"/*; do
            [ -f "$src" ] || continue
            
            local basename="$(basename "$src")"
            local name="${basename%.*}"
            local dest="${PUBLIC_DIR}/img/covers/${name}.webp"
            
            if [ "$WEBP_AVAILABLE" != true ]; then
                if [ ! -f "$dest" ] || [ "$src" -nt "$dest" ]; then
                    cp "$src" "$dest"
                fi
                continue
            fi
            
            local src_ext="${basename##*.}"
            local src_lower="$(echo "$src_ext" | tr '[:upper:]' '[:lower:]')"
            
            if [ "$src_lower" = "webp" ]; then
                if [ ! -f "$dest" ] || [ "$src" -nt "$dest" ]; then
                    cp "$src" "$dest"
                fi
                continue
            fi
            
            if [ ! -f "$dest" ] || [ "$src" -nt "$dest" ]; then
                log_verbose "Convirtiendo: $basename → ${name}.webp"
                if cwebp -q 80 "$src" -o "$dest" > /dev/null 2>&1; then
                    log_verbose "Convertido: ${name}.webp"
                else
                    log_warning "Error convirtiendo $basename, copiando original"
                    cp "$src" "$dest"
                fi
            fi
        done
        log_verbose "Portadas procesadas"
    fi
    
    # Copiar PDFs desde assets/pdf/
    if [ -d "$PDF_DIR" ]; then
        cp -r "$PDF_DIR"/* "${PUBLIC_DIR}/pdf/" 2>/dev/null || true
        log_verbose "PDFs copiados a public/pdf/"
    fi
    
    log_success "Archivos estáticos copiados"
}

# Generar CSS principal
generate_css() {
    log_info "Generando CSS..."
    
    local theme_vars
    theme_vars=$(generate_theme_css)
    
    cat > "${PUBLIC_DIR}/css/styles.css" << EOF
/*===============================================================================
 * Biblioteca - Núcleo Linux UAGRM
 * CSS Principal - Tema Oscuro con Estética Hacker/Linux
 *===============================================================================*/

:root {
    /* Colores del tema */
${theme_vars}
    
    /* Espaciado */
    --spacing-xs: 0.25rem;
    --spacing-sm: 0.5rem;
    --spacing-md: 1rem;
    --spacing-lg: 1.5rem;
    --spacing-xl: 2rem;
    --spacing-2xl: 3rem;
    
    /* Border radius */
    --radius-sm: 4px;
    --radius-md: 8px;
    --radius-lg: 12px;
    --radius-xl: 16px;
    
    /* Transiciones */
    --transition-fast: 150ms ease;
    --transition-normal: 250ms ease;
    --transition-slow: 350ms ease;
    
    /* Tipografía */
    --font-mono: 'JetBrains Mono', 'Fira Code', 'Consolas', monospace;
    --font-sans: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
}

/* Reset */
*, *::before, *::after {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
}

html {
    scroll-behavior: smooth;
    overflow-x: hidden;
}

body {
    font-family: var(--font-sans);
    background: var(--bg-primary);
    color: var(--text-primary);
    line-height: 1.6;
    min-height: 100vh;
    overflow-x: hidden;
}

/* Header */
.header {
    background: var(--glass-bg);
    backdrop-filter: var(--glass-blur);
    border-bottom: 1px solid var(--glass-border);
    padding: var(--spacing-md) var(--spacing-xl);
    position: sticky;
    top: 0;
    z-index: 1000;
}

.header-content {
    max-width: 1400px;
    margin: 0 auto;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.logo {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    text-decoration: none;
    color: var(--text-primary);
}

.logo-icon {
    width: 40px;
    height: 40px;
    fill: var(--accent-green);
}

.logo-text {
    font-family: var(--font-mono);
    font-size: 1.2rem;
    font-weight: 700;
}

/* Navegación */
.nav {
    display: flex;
    gap: var(--spacing-lg);
}

.nav a {
    color: var(--text-secondary);
    text-decoration: none;
    font-size: 0.9rem;
    transition: color var(--transition-fast);
}

.nav a:hover {
    color: var(--accent-green);
}

.btn-nav-external {
    display: inline-flex;
    align-items: center;
    gap: var(--spacing-xs);
    padding: var(--spacing-xs) var(--spacing-md);
    background: var(--accent-green);
    color: var(--bg-primary) !important;
    border-radius: var(--radius-md);
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    text-decoration: none;
    transition: all var(--transition-fast);
}

.btn-nav-external:hover {
    background: var(--accent-cyan);
    box-shadow: var(--shadow-glow-green);
}

/* Hamburger menu toggle */
.menu-toggle {
    display: none;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    background: transparent;
    border: 1px solid var(--border-color);
    border-radius: var(--radius-md);
    cursor: pointer;
    z-index: 2002;
    transition: all var(--transition-fast);
}

.menu-toggle:hover {
    border-color: var(--accent-green);
}

.menu-toggle svg {
    width: 24px;
    height: 24px;
    stroke: var(--text-primary);
    fill: none;
    stroke-width: 2;
    stroke-linecap: round;
    stroke-linejoin: round;
}

/* Nav overlay */
.nav-overlay {
    display: none;
}

/* Contenedor principal */
.container {
    max-width: 1400px;
    margin: 0 auto;
    padding: var(--spacing-xl);
}

/* Hero Section */
.hero {
    text-align: center;
    padding: var(--spacing-xl) 0;
    margin-bottom: var(--spacing-lg);
}

.hero h1 {
    font-size: 2.5rem;
    font-weight: 700;
    margin-bottom: var(--spacing-md);
    background: linear-gradient(135deg, var(--accent-green), var(--accent-cyan));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
}

.hero p {
    font-size: 1.1rem;
    color: var(--text-secondary);
    max-width: 600px;
    margin: 0 auto;
}

/* Botones */
.btn {
    display: inline-flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-sm) var(--spacing-lg);
    border-radius: var(--radius-md);
    font-family: var(--font-mono);
    font-size: 0.9rem;
    font-weight: 500;
    text-decoration: none;
    cursor: pointer;
    transition: all var(--transition-fast);
    border: none;
}

.btn-primary {
    background: var(--accent-green);
    color: var(--bg-primary);
}

.btn-primary:hover {
    background: var(--accent-cyan);
    box-shadow: var(--shadow-glow-green);
}

.btn-secondary {
    background: transparent;
    color: var(--accent-green);
    border: 1px solid var(--accent-green);
}

.btn-secondary:hover {
    background: rgba(0, 255, 65, 0.1);
}

/* Buscador */
.search-container {
    max-width: 600px;
    margin: 0 auto var(--spacing-2xl);
}

.search-box {
    position: relative;
}

.search-input {
    width: 100%;
    padding: var(--spacing-md) var(--spacing-lg);
    padding-left: 3rem;
    background: var(--bg-secondary);
    border: 1px solid var(--border-color);
    border-radius: var(--radius-lg);
    color: var(--text-primary);
    font-size: 1rem;
    transition: all var(--transition-fast);
}

.search-input:focus {
    outline: none;
    border-color: var(--accent-green);
    box-shadow: var(--shadow-glow-green);
}

.search-icon {
    position: absolute;
    left: var(--spacing-md);
    top: 50%;
    transform: translateY(-50%);
    width: 20px;
    height: 20px;
    fill: var(--text-muted);
}

/* Grid de Libros */
.books-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: var(--spacing-xl);
    margin-top: var(--spacing-xl);
}

/* Card de Libro */
.book-card {
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: var(--radius-lg);
    overflow: hidden;
    transition: all var(--transition-normal);
    display: flex;
    flex-direction: column;
}

.book-card:hover {
    transform: translateY(-4px);
    border-color: var(--accent-green);
    box-shadow: var(--shadow-glow-green);
}

.book-cover {
    width: 100%;
    aspect-ratio: 3/4;
    object-fit: cover;
    background: var(--bg-tertiary);
}

.book-info {
    padding: var(--spacing-lg);
    display: flex;
    flex-direction: column;
    flex: 1;
}

.book-category {
    display: inline-block;
    padding: var(--spacing-xs) var(--spacing-sm);
    background: rgba(0, 255, 65, 0.1);
    color: var(--accent-green);
    font-size: 0.75rem;
    font-family: var(--font-mono);
    border-radius: var(--radius-sm);
    margin-bottom: var(--spacing-sm);
    align-self: flex-start;
}

.book-title {
    font-size: 1.1rem;
    font-weight: 600;
    margin-bottom: var(--spacing-sm);
    color: var(--text-primary);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    min-height: 3.3em;
}

.book-meta {
    display: flex;
    gap: var(--spacing-md);
    font-size: 0.85rem;
    color: var(--text-muted);
    margin-bottom: var(--spacing-md);
    min-height: 1.5em;
}

.book-actions {
    display: flex;
    gap: var(--spacing-sm);
    margin-top: auto;
}

.book-actions .btn {
    flex: 1;
    justify-content: center;
    padding: var(--spacing-sm);
    font-size: 0.85rem;
}

/* Footer */
.footer {
    background: var(--bg-secondary);
    border-top: 1px solid var(--border-color);
    padding: var(--spacing-2xl) var(--spacing-xl);
    margin-top: var(--spacing-2xl);
}

.footer-content {
    max-width: 1400px;
    margin: 0 auto;
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: var(--spacing-xl);
}

.footer-section h3 {
    font-size: 1rem;
    font-weight: 600;
    margin-bottom: var(--spacing-md);
    color: var(--text-primary);
}

.footer-section p,
.footer-section a {
    color: var(--text-secondary);
    text-decoration: none;
    font-size: 0.9rem;
    line-height: 1.8;
}

.footer-section a:hover {
    color: var(--accent-green);
}

.footer-bottom {
    max-width: 1400px;
    margin: var(--spacing-xl) auto 0;
    padding-top: var(--spacing-xl);
    border-top: 1px solid var(--border-color);
    text-align: center;
    color: var(--text-muted);
    font-size: 0.85rem;
}

/* Responsive */
@media (max-width: 768px) {
    .menu-toggle {
        display: flex;
    }
    
    .menu-toggle.active svg line:nth-child(1) {
        transform: rotate(45deg) translate(5px, 5px);
    }
    
    .menu-toggle.active svg line:nth-child(2) {
        opacity: 0;
    }
    
    .menu-toggle.active svg line:nth-child(3) {
        transform: rotate(-45deg) translate(5px, -5px);
    }
    
    .nav {
        position: fixed;
        top: 0;
        right: -300px;
        width: 280px;
        height: 100%;
        height: 100dvh;
        background: var(--bg-secondary);
        flex-direction: column;
        gap: 0;
        padding: var(--spacing-xl);
        padding-top: 5rem;
        z-index: 2001;
        transition: right 0.3s ease;
        box-shadow: var(--shadow-lg);
        overflow-y: auto;
        overflow-x: hidden;
    }
    
    .nav.active {
        right: 0;
    }
    
    .nav a {
        padding: var(--spacing-md) 0;
        border-bottom: 1px solid var(--border-color);
        font-size: 1rem;
    }
    
    .nav a:last-child {
        border-bottom: none;
    }
    
    .nav .btn-nav-external {
        margin-top: var(--spacing-md);
        border-bottom: none;
        text-align: center;
        justify-content: center;
    }
    
    .nav-overlay {
        display: none;
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        height: 100dvh;
        background: rgba(0, 0, 0, 0.6);
        z-index: 2000;
        opacity: 0;
        transition: opacity 0.3s ease;
    }
    
    .nav-overlay.active {
        display: block;
        opacity: 1;
    }
    
    .header-content {
        flex-wrap: nowrap;
    }
    
    .hero h1 {
        font-size: 1.8rem;
    }
    
    .books-grid {
        grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
    }
    
    .book-actions {
        flex-direction: column;
    }
    
    .footer-content {
        grid-template-columns: 1fr;
        text-align: center;
    }
}

@media (max-width: 480px) {
    .container {
        padding: var(--spacing-md);
    }
    
    .books-grid {
        grid-template-columns: 1fr;
    }
    
    .hero h1 {
        font-size: 1.5rem;
    }
    
    .hero p {
        font-size: 0.95rem;
    }
    
    .search-input {
        font-size: 0.9rem;
        padding: var(--spacing-sm) var(--spacing-md);
        padding-left: 2.5rem;
    }
    
    .book-info {
        padding: var(--spacing-md);
    }
    
    .book-title {
        font-size: 1rem;
        -webkit-line-clamp: 2;
        min-height: 3em;
    }
    
    .footer {
        padding: var(--spacing-xl) var(--spacing-md);
    }
}

/* Animaciones */
@keyframes fadeIn {
    from { opacity: 0; transform: translateY(10px); }
    to { opacity: 1; transform: translateY(0); }
}

.book-card {
    animation: fadeIn 0.3s ease forwards;
}

/* Transiciones del buscador */
.books-grid {
    transition: opacity 0.2s ease;
}

.no-results {
    grid-column: 1 / -1;
    text-align: center;
    padding: var(--spacing-2xl);
    color: var(--text-muted);
    font-size: 1rem;
    animation: fadeIn 0.3s ease forwards;
}

/* Accesibilidad */
@media (prefers-reduced-motion: reduce) {
    * {
        animation: none !important;
        transition: none !important;
    }
}

.sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
}

/* Focus visible */
:focus-visible {
    outline: 2px solid var(--accent-green);
    outline-offset: 2px;
}

/* Scrollbar */
::-webkit-scrollbar {
    width: 8px;
}

::-webkit-scrollbar-track {
    background: var(--bg-secondary);
}

::-webkit-scrollbar-thumb {
    background: var(--border-color);
    border-radius: 4px;
}

::-webkit-scrollbar-thumb:hover {
    background: var(--accent-green);
}

/* About Page */
.about-content {
    max-width: 800px;
    margin: 0 auto;
}

.about-section {
    margin-bottom: var(--spacing-2xl);
}

.about-section h2 {
    font-size: 1.5rem;
    font-weight: 600;
    margin-bottom: var(--spacing-md);
    color: var(--accent-green);
}

.about-section p {
    color: var(--text-secondary);
    line-height: 1.8;
    margin-bottom: var(--spacing-md);
}

.about-section ul {
    list-style: none;
    padding: 0;
}

.about-section li {
    padding: var(--spacing-sm) 0;
    padding-left: var(--spacing-lg);
    position: relative;
    color: var(--text-secondary);
}

.about-section li::before {
    content: ">";
    position: absolute;
    left: 0;
    color: var(--accent-green);
    font-family: var(--font-mono);
}

/* Filtros */
.filter-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: var(--spacing-md);
    margin-bottom: var(--spacing-lg);
}

.filter-toggle-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 8px 16px;
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: var(--radius-lg);
    color: var(--text-primary);
    font-size: 0.9rem;
    cursor: pointer;
    transition: all var(--transition-fast);
    position: relative;
}

.filter-toggle-btn:hover {
    border-color: var(--accent-green);
}

.filter-toggle-btn svg {
    width: 16px;
    height: 16px;
}

.filter-count-badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 18px;
    height: 18px;
    padding: 0 4px;
    background: var(--accent-green);
    color: var(--bg-primary);
    font-size: 0.7rem;
    font-weight: 600;
    border-radius: 50%;
    line-height: 1;
}

.filter-count-badge:empty {
    display: none;
}

.filter-clear-btn {
    display: none;
    align-items: center;
    gap: 4px;
    padding: 6px 12px;
    background: transparent;
    border: 1px solid var(--border-color);
    border-radius: var(--radius-md);
    color: var(--text-muted);
    font-size: 0.8rem;
    cursor: pointer;
    transition: all var(--transition-fast);
}

.filter-clear-btn:hover {
    border-color: var(--danger);
    color: var(--danger);
}

.filter-panel {
    display: none;
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: var(--radius-lg);
    padding: var(--spacing-lg);
    margin-bottom: var(--spacing-xl);
    animation: fadeIn 0.2s ease forwards;
}

.filter-panel.active {
    display: block;
}

.filter-group {
    margin-bottom: var(--spacing-md);
}

.filter-group:last-child {
    margin-bottom: 0;
}

.filter-group h4 {
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--text-primary);
    margin-bottom: var(--spacing-sm);
}

.filter-chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
}

.filter-chip {
    display: inline-flex;
    align-items: center;
    padding: 5px 12px;
    background: var(--bg-secondary);
    border: 1px solid var(--border-color);
    border-radius: 20px;
    color: var(--text-secondary);
    font-size: 0.8rem;
    cursor: pointer;
    transition: all var(--transition-fast);
}

.filter-chip:hover {
    border-color: var(--accent-green);
    color: var(--accent-green);
}

.filter-chip.active {
    background: var(--accent-green);
    border-color: var(--accent-green);
    color: var(--bg-primary);
    font-weight: 500;
}

/* Paginación */
.pagination {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    margin-top: var(--spacing-2xl);
    flex-wrap: wrap;
}

.page-btn {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 8px 14px;
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: var(--radius-md);
    color: var(--text-secondary);
    font-size: 0.85rem;
    cursor: pointer;
    transition: all var(--transition-fast);
}

.page-btn:hover:not(:disabled) {
    border-color: var(--accent-green);
    color: var(--accent-green);
}

.page-btn.active {
    background: var(--accent-green);
    border-color: var(--accent-green);
    color: var(--bg-primary);
    font-weight: 600;
}

.page-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
}

.page-btn svg {
    width: 14px;
    height: 14px;
}

.page-ellipsis {
    color: var(--text-muted);
    padding: 0 4px;
    font-size: 0.85rem;
}

/* Responsive filtros y paginación */
@media (max-width: 768px) {
    .filter-bar {
        flex-direction: column;
        align-items: stretch;
    }
    
    .filter-toggle-btn {
        justify-content: center;
    }
    
    .page-btn {
        padding: 6px 10px;
        font-size: 0.8rem;
    }
    
    .page-btn span.page-label {
        display: none;
    }
}

@media (max-width: 480px) {
    .filter-chips {
        gap: 4px;
    }
    
    .filter-chip {
        padding: 4px 10px;
        font-size: 0.75rem;
    }
    
    .pagination {
        gap: 4px;
    }
    
    .page-btn {
        padding: 6px 8px;
        min-width: 32px;
        justify-content: center;
    }
}

/* Visor PDF */
.pdf-viewer-overlay {
    display: none;
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    height: 100dvh;
    background: #1a1a1a;
    z-index: 3000;
    opacity: 0;
    transition: opacity 0.2s ease;
}

.pdf-viewer-overlay.active {
    display: flex;
    flex-direction: column;
    opacity: 1;
}

.pdf-viewer-header {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    background: var(--bg-secondary);
    border-bottom: 1px solid var(--border-color);
    flex-shrink: 0;
    z-index: 1;
    min-height: 48px;
}

.pdf-viewer-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    min-width: 36px;
    background: transparent;
    border: 1px solid var(--border-color);
    border-radius: var(--radius-md);
    color: var(--text-primary);
    cursor: pointer;
    transition: all var(--transition-fast);
    flex-shrink: 0;
}

.pdf-viewer-close:hover {
    background: rgba(255, 255, 255, 0.1);
    border-color: var(--accent-green);
    color: var(--accent-green);
}

.pdf-viewer-close svg {
    width: 18px;
    height: 18px;
}

.pdf-viewer-title {
    font-size: 0.85rem;
    font-weight: 500;
    color: var(--text-primary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    flex: 1;
    min-width: 0;
}

.pdf-viewer-toolbar {
    display: flex;
    align-items: center;
    gap: 4px;
    flex-shrink: 0;
}

.pdf-tool-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 34px;
    height: 34px;
    min-width: 34px;
    background: transparent;
    border: 1px solid var(--border-color);
    border-radius: var(--radius-sm);
    color: var(--text-secondary);
    cursor: pointer;
    transition: all var(--transition-fast);
}

.pdf-tool-btn:hover {
    background: rgba(255, 255, 255, 0.08);
    color: var(--text-primary);
    border-color: var(--accent-green);
}

.pdf-tool-btn:disabled {
    opacity: 0.3;
    cursor: not-allowed;
}

.pdf-tool-btn:disabled:hover {
    background: transparent;
    color: var(--text-secondary);
    border-color: var(--border-color);
}

.pdf-page-info {
    font-size: 0.8rem;
    color: var(--text-muted);
    white-space: nowrap;
    padding: 0 4px;
    font-family: var(--font-mono);
}

.pdf-zoom-label {
    font-size: 0.75rem;
    color: var(--text-muted);
    white-space: nowrap;
    min-width: 40px;
    text-align: center;
    font-family: var(--font-mono);
}

.pdf-toolbar-sep {
    width: 1px;
    height: 20px;
    background: var(--border-color);
    margin: 0 2px;
}

.pdf-viewer-body {
    flex: 1;
    position: relative;
    overflow: hidden;
}

.pdf-viewer-loading {
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    color: var(--text-muted);
    font-size: 0.9rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    z-index: 1;
}

.pdf-spinner {
    width: 32px;
    height: 32px;
    border: 3px solid var(--border-color);
    border-top-color: var(--accent-green);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
}

@keyframes spin {
    to { transform: rotate(360deg); }
}

.pdf-viewer-scroll {
    width: 100%;
    height: 100%;
    overflow-y: auto;
    overflow-x: auto;
    background: #2a2a2a;
    -webkit-overflow-scrolling: touch;
    touch-action: pan-y pan-x;
}

.pdf-pages-container {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    padding: 16px 0;
    transform-origin: top center;
    transition: transform 0.1s ease-out;
    will-change: transform;
}

.pdf-page-wrapper {
    position: relative;
    line-height: 0;
    background: var(--bg-secondary, #f8f9fa);
    border-radius: 2px;
    overflow: hidden;
}

.pdf-page-wrapper canvas {
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.5);
    display: block;
}

/* Responsive visor PDF */
@media (max-width: 768px) {
    .pdf-viewer-header {
        padding: 6px 8px;
        gap: 6px;
        flex-wrap: nowrap;
        overflow-x: auto;
        -webkit-overflow-scrolling: touch;
    }
    
    .pdf-viewer-title {
        display: none;
    }
    
    .pdf-tool-btn {
        width: 36px;
        height: 36px;
        min-width: 36px;
    }
    
    .pdf-toolbar-sep {
        display: none;
    }
    
    .pdf-pages-container {
        gap: 8px;
        padding: 8px 0;
    }
}

@media (max-width: 480px) {
    .pdf-viewer-overlay.active {
        padding-top: env(safe-area-inset-top);
        padding-bottom: env(safe-area-inset-bottom);
    }
    
    .pdf-viewer-header {
        padding: 6px 8px;
        padding-top: calc(6px + env(safe-area-inset-top));
        gap: 4px;
        min-height: 44px;
    }
    
    .pdf-viewer-close {
        width: 34px;
        height: 34px;
        min-width: 34px;
    }
    
    .pdf-tool-btn {
        width: 38px;
        height: 38px;
        min-width: 38px;
    }
    
    .pdf-page-info {
        font-size: 0.75rem;
    }
    
    .pdf-zoom-label {
        font-size: 0.7rem;
        min-width: 36px;
    }
    
    .pdf-pages-container {
        gap: 6px;
        padding: 4px 0;
    }
}
EOF
    
    log_success "CSS generado"
}

# Generar JavaScript principal
generate_js() {
    log_info "Generando JavaScript..."
    
    cat > "${PUBLIC_DIR}/js/app.js" << 'EOF'
/*===============================================================================
 * Biblioteca - Núcleo Linux UAGRM
 * JavaScript Principal
 *===============================================================================*/

// Variables globales
let allCards = [];
let filteredCards = [];
let currentPage = 1;
let searchQuery = '';
let activeCategory = '';
let activeTags = [];

// Configuración de paginación
const CONFIG = window.CATALOG_CONFIG || { booksPerPage: { desktop: 8, tablet: 6, mobile: 4 } };

function getBooksPerPage() {
    const w = window.innerWidth;
    if (w <= 768) return CONFIG.booksPerPage.mobile;
    if (w <= 1024) return CONFIG.booksPerPage.tablet;
    return CONFIG.booksPerPage.desktop;
}

// Inicialización
document.addEventListener('DOMContentLoaded', () => {
    allCards = Array.from(document.querySelectorAll('#books-container .book-card'));
    buildFilters();
    applyFilters();
    setupSearch();
    setupMenu();
    window.addEventListener('resize', () => {
        currentPage = 1;
        renderPage();
    });
});

// Menú móvil
function setupMenu() {
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            closePdfViewer();
            closeMenu();
            closeFilters();
        }
    });
    
    const navLinks = document.querySelectorAll('#nav-menu a');
    navLinks.forEach(link => {
        link.addEventListener('click', () => {
            closeMenu();
        });
    });
}

function toggleMenu() {
    const nav = document.getElementById('nav-menu');
    const overlay = document.getElementById('nav-overlay');
    const toggle = document.querySelector('.menu-toggle');
    
    if (nav && overlay) {
        const isActive = nav.classList.toggle('active');
        overlay.classList.toggle('active');
        toggle.classList.toggle('active');
        document.body.style.overflow = isActive ? 'hidden' : '';
        document.documentElement.style.overflow = isActive ? 'hidden' : '';
    }
}

function closeMenu() {
    const nav = document.getElementById('nav-menu');
    const overlay = document.getElementById('nav-overlay');
    const toggle = document.querySelector('.menu-toggle');
    
    if (nav && overlay) {
        nav.classList.remove('active');
        overlay.classList.remove('active');
        toggle.classList.remove('active');
        document.body.style.overflow = '';
        document.documentElement.style.overflow = '';
    }
}

// Configurar buscador
function setupSearch() {
    const searchInput = document.getElementById('search-input');
    if (!searchInput) return;
    
    searchInput.addEventListener('input', (e) => {
        searchQuery = normalizeText(e.target.value);
        currentPage = 1;
        applyFilters();
    });
}

// Normalizar texto (quitar acentos, minúsculas)
function normalizeText(text) {
    return text
        .toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .trim();
}

// Aplicar todos los filtros (search + category + tags)
function applyFilters() {
    filteredCards = allCards.filter(card => {
        if (searchQuery) {
            const title = normalizeText(card.dataset.title || '');
            const category = normalizeText(card.dataset.category || '');
            const tags = (card.dataset.tags || '').split(',').map(t => normalizeText(t)).join(' ');
            if (!title.includes(searchQuery) && !category.includes(searchQuery) && !tags.includes(searchQuery)) {
                return false;
            }
        }
        if (activeCategory && normalizeText(card.dataset.category || '') !== normalizeText(activeCategory)) {
            return false;
        }
        if (activeTags.length > 0) {
            const cardTags = (card.dataset.tags || '').split(',').map(t => normalizeText(t));
            for (const tag of activeTags) {
                if (!cardTags.includes(normalizeText(tag))) return false;
            }
        }
        return true;
    });
    
    renderPage();
}

// Filtros ya están en el HTML estático
function buildFilters() {
    updateFilterUI();
}

function toggleCategory(cat) {
    activeCategory = activeCategory === cat ? '' : cat;
    currentPage = 1;
    applyFilters();
    updateFilterUI();
}

function toggleTag(tag) {
    const idx = activeTags.indexOf(tag);
    if (idx === -1) {
        activeTags.push(tag);
    } else {
        activeTags.splice(idx, 1);
    }
    currentPage = 1;
    applyFilters();
    updateFilterUI();
}

function updateFilterUI() {
    document.querySelectorAll('#filter-categories .filter-chip').forEach(el => {
        el.classList.toggle('active', el.dataset.category === activeCategory);
    });
    document.querySelectorAll('#filter-tags .filter-chip').forEach(el => {
        el.classList.toggle('active', activeTags.includes(el.dataset.tag));
    });
    
    const clearBtn = document.getElementById('filter-clear');
    if (clearBtn) {
        clearBtn.style.display = (activeCategory || activeTags.length > 0) ? 'inline-flex' : 'none';
    }
    
    updateFilterCount();
}

function clearAllFilters() {
    activeCategory = '';
    activeTags = [];
    currentPage = 1;
    applyFilters();
    updateFilterUI();
}

function updateFilterCount() {
    const count = (activeCategory ? 1 : 0) + activeTags.length;
    const badge = document.getElementById('filter-count');
    if (badge) {
        badge.textContent = count > 0 ? count : '';
        badge.style.display = count > 0 ? 'inline-flex' : 'none';
    }
}

function toggleFilters() {
    const panel = document.getElementById('filter-panel');
    if (panel) {
        panel.classList.toggle('active');
    }
}

function closeFilters() {
    const panel = document.getElementById('filter-panel');
    if (panel) {
        panel.classList.remove('active');
    }
}

// Renderizar página actual
function renderPage() {
    const container = document.getElementById('books-container');
    if (!container) return;
    
    const perPage = getBooksPerPage();
    const totalPages = Math.ceil(filteredCards.length / perPage);
    
    if (currentPage > totalPages) currentPage = totalPages || 1;
    
    const start = (currentPage - 1) * perPage;
    
    container.style.opacity = '0';
    
    setTimeout(() => {
        allCards.forEach(card => card.style.display = 'none');
        
        if (filteredCards.length === 0) {
            let noResults = container.querySelector('.no-results');
            if (!noResults) {
                noResults = document.createElement('div');
                noResults.className = 'no-results';
                noResults.innerHTML = '<p>No se encontraron libros que coincidan con tu búsqueda.</p>';
                container.appendChild(noResults);
            }
            noResults.style.display = '';
        } else {
            const existing = container.querySelector('.no-results');
            if (existing) existing.style.display = 'none';
            
            for (let i = start; i < Math.min(start + perPage, filteredCards.length); i++) {
                filteredCards[i].style.display = '';
            }
        }
        
        renderPagination(totalPages);
        
        requestAnimationFrame(() => {
            container.style.opacity = '1';
        });
    }, 150);
}

// Renderizar controles de paginación
function renderPagination(totalPages) {
    const pag = document.getElementById('pagination');
    if (!pag) return;
    
    if (totalPages <= 1) {
        pag.innerHTML = '';
        pag.style.display = 'none';
        return;
    }
    
    pag.style.display = 'flex';
    
    let html = '';
    
    // Botón anterior
    html += `<button class="page-btn" ${currentPage === 1 ? 'disabled' : ''} onclick="goToPage(${currentPage - 1})">
        <svg viewBox="0 0 24 24" width="16" height="16"><path d="M15 18l-6-6 6-6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
        Anterior
    </button>`;
    
    // Números de página
    const maxVisible = 5;
    let startPage = Math.max(1, currentPage - Math.floor(maxVisible / 2));
    let endPage = Math.min(totalPages, startPage + maxVisible - 1);
    
    if (endPage - startPage < maxVisible - 1) {
        startPage = Math.max(1, endPage - maxVisible + 1);
    }
    
    if (startPage > 1) {
        html += `<button class="page-btn" onclick="goToPage(1)">1</button>`;
        if (startPage > 2) html += `<span class="page-ellipsis">...</span>`;
    }
    
    for (let i = startPage; i <= endPage; i++) {
        html += `<button class="page-btn ${i === currentPage ? 'active' : ''}" onclick="goToPage(${i})">${i}</button>`;
    }
    
    if (endPage < totalPages) {
        if (endPage < totalPages - 1) html += `<span class="page-ellipsis">...</span>`;
        html += `<button class="page-btn" onclick="goToPage(${totalPages})">${totalPages}</button>`;
    }
    
    // Botón siguiente
    html += `<button class="page-btn" ${currentPage === totalPages ? 'disabled' : ''} onclick="goToPage(${currentPage + 1})">
        Siguiente
        <svg viewBox="0 0 24 24" width="16" height="16"><path d="M9 18l6-6-6-6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
    </button>`;
    
    pag.innerHTML = html;
}

function goToPage(page) {
    currentPage = page;
    renderPage();
    window.scrollTo({ top: document.getElementById('books-container').offsetTop - 80, behavior: 'smooth' });
}

// Visor PDF
let pdfDoc = null;
let pdfCurrentPage = 1;
let pdfScale = 1;
let pdfBaseScale = 1;
let pdfRendering = false;
let pdfHammer = null;
let pdfTouchActive = false;
let pdfPinchStartScale = 1;
let pdfContainer = null;
let pdfScrollEl = null;
let pdfFitWidthScale = 1;
let pdfPageDims = [];
let pdfRenderedPages = {};
let pdfVisibleObserver = null;
let pdfScrollTick = false;

function openPdfViewer(pdfUrl, title) {
    var overlay = document.getElementById('pdf-viewer');
    var titleEl = document.getElementById('pdf-viewer-title');
    var loadingEl = document.getElementById('pdf-loading');
    pdfScrollEl = document.getElementById('pdf-scroll');
    
    if (!overlay || !titleEl) return;
    
    titleEl.textContent = title;
    pdfDoc = null;
    pdfCurrentPage = 1;
    pdfScale = 1;
    pdfBaseScale = 1;
    pdfPageDims = [];
    pdfRenderedPages = {};
    
    if (pdfVisibleObserver) {
        pdfVisibleObserver.disconnect();
        pdfVisibleObserver = null;
    }
    
    var existingContainer = document.getElementById('pdf-pages-container');
    if (existingContainer) existingContainer.remove();
    
    pdfContainer = document.createElement('div');
    pdfContainer.id = 'pdf-pages-container';
    pdfContainer.className = 'pdf-pages-container';
    if (pdfScrollEl) pdfScrollEl.appendChild(pdfContainer);
    
    if (loadingEl) loadingEl.style.display = '';
    if (pdfScrollEl) pdfScrollEl.scrollTop = 0;
    
    updatePdfPageInfo();
    updatePdfZoomLabel();
    
    overlay.classList.add('active');
    document.body.style.overflow = 'hidden';
    document.documentElement.style.overflow = 'hidden';
    
    if (typeof pdfjsLib === 'undefined') {
        if (loadingEl) loadingEl.innerHTML = '<span>Error: no se pudo cargar el visor PDF</span>';
        return;
    }
    
    var loadingTask = pdfjsLib.getDocument(pdfUrl);
    loadingTask.promise.then(function(pdf) {
        pdfDoc = pdf;
        updatePdfPageInfo();
        pdfInitDocument();
    }).catch(function(err) {
        console.error('Error loading PDF:', err);
        if (loadingEl) loadingEl.innerHTML = '<span>Error al cargar el PDF</span>';
    });
}

function pdfInitDocument() {
    if (!pdfDoc || !pdfContainer) return;
    
    var numPages = pdfDoc.numPages;
    var scrollWidth = pdfScrollEl ? pdfScrollEl.clientWidth - 32 : 800;
    
    var dimPromises = [];
    for (var i = 1; i <= numPages; i++) {
        dimPromises.push(pdfDoc.getPage(i).then(function(page) {
            var v = page.getViewport({ scale: 1 });
            return { num: page.pageNumber, width: v.width, height: v.height };
        }).catch(function(err) {
            console.warn('Error getting dimensions for page:', err);
            return null;
        }));
    }
    
    Promise.all(dimPromises).then(function(results) {
        pdfPageDims = [];
        var validResults = results.filter(function(r) { return r !== null; });
        validResults.forEach(function(r) {
            pdfPageDims[r.num - 1] = { width: r.width, height: r.height };
        });
        
        if (pdfPageDims.length === 0) {
            var loadingEl = document.getElementById('pdf-loading');
            if (loadingEl) loadingEl.innerHTML = '<span>Error al cargar las páginas del PDF</span>';
            return;
        }
        
        pdfBaseScale = scrollWidth / pdfPageDims[0].width;
        pdfScale = pdfBaseScale;
        pdfFitWidthScale = pdfBaseScale;
        updatePdfZoomLabel();
        
        pdfCreatePlaceholders();
        pdfRenderVisiblePages();
        pdfSetupObserver();
        initPdfGestures();
        
        var loadingEl = document.getElementById('pdf-loading');
        if (loadingEl) loadingEl.style.display = 'none';
    }).catch(function(err) {
        console.error('Error loading page dimensions:', err);
        var loadingEl = document.getElementById('pdf-loading');
        if (loadingEl) loadingEl.innerHTML = '<span>Error al cargar las páginas del PDF</span>';
    });
}

function pdfCreatePlaceholders() {
    if (!pdfContainer || !pdfPageDims.length) return;
    
    pdfContainer.innerHTML = '';
    
    for (var i = 0; i < pdfPageDims.length; i++) {
        var dim = pdfPageDims[i];
        var scaledWidth = dim.width * pdfScale;
        var scaledHeight = dim.height * pdfScale;
        
        var wrapper = document.createElement('div');
        wrapper.className = 'pdf-page-wrapper';
        wrapper.setAttribute('data-page', i + 1);
        wrapper.style.width = Math.round(scaledWidth) + 'px';
        wrapper.style.height = Math.round(scaledHeight) + 'px';
        
        pdfContainer.appendChild(wrapper);
    }
}

function pdfSetupObserver() {
    if (pdfVisibleObserver) {
        pdfVisibleObserver.disconnect();
    }
    
    if (!pdfScrollEl || typeof IntersectionObserver === 'undefined') {
        pdfRenderVisiblePages();
        return;
    }
    
    pdfVisibleObserver = new IntersectionObserver(function(entries) {
        entries.forEach(function(entry) {
            if (entry.isIntersecting) {
                var num = parseInt(entry.target.getAttribute('data-page'));
                pdfRenderPageToCanvas(num);
            }
        });
    }, {
        root: pdfScrollEl,
        rootMargin: '400px 0px',
        threshold: 0
    });
    
    var wrappers = pdfContainer.querySelectorAll('.pdf-page-wrapper');
    wrappers.forEach(function(w) {
        pdfVisibleObserver.observe(w);
    });
}

function pdfRenderVisiblePages() {
    if (!pdfScrollEl || !pdfContainer) return;
    
    var scrollTop = pdfScrollEl.scrollTop;
    var viewHeight = pdfScrollEl.clientHeight;
    var buffer = 400;
    
    var wrappers = pdfContainer.querySelectorAll('.pdf-page-wrapper');
    wrappers.forEach(function(wrapper) {
        var top = wrapper.offsetTop;
        var bottom = top + wrapper.offsetHeight;
        
        if (bottom >= scrollTop - buffer && top <= scrollTop + viewHeight + buffer) {
            var num = parseInt(wrapper.getAttribute('data-page'));
            pdfRenderPageToCanvas(num);
        }
    });
}

function pdfRenderPageToCanvas(num) {
    if (!pdfDoc || pdfRenderedPages[num]) return;
    
    var wrapper = pdfContainer.querySelector('[data-page="' + num + '"]');
    if (!wrapper || wrapper.querySelector('canvas')) return;
    
    pdfRenderedPages[num] = true;
    
    pdfDoc.getPage(num).then(function(page) {
        if (!pdfDoc) return;
        var viewport = page.getViewport({ scale: pdfScale });
        
        var canvas = document.createElement('canvas');
        canvas.width = viewport.width;
        canvas.height = viewport.height;
        canvas.className = 'pdf-page-canvas';
        
        wrapper.innerHTML = '';
        wrapper.appendChild(canvas);
        
        page.render({ canvasContext: canvas.getContext('2d'), viewport: viewport });
    }).catch(function() {
        pdfRenderedPages[num] = false;
    });
}

function pdfRerenderVisiblePages() {
    if (!pdfDoc || !pdfContainer) return;
    
    var scrollTop = pdfScrollEl ? pdfScrollEl.scrollTop : 0;
    var scrollHeight = pdfScrollEl ? pdfScrollEl.scrollHeight : 0;
    
    pdfRenderedPages = {};
    
    var wrappers = pdfContainer.querySelectorAll('.pdf-page-wrapper');
    wrappers.forEach(function(wrapper) {
        var num = parseInt(wrapper.getAttribute('data-page'));
        var dim = pdfPageDims[num - 1];
        if (!dim) return;
        
        wrapper.style.width = Math.round(dim.width * pdfScale) + 'px';
        wrapper.style.height = Math.round(dim.height * pdfScale) + 'px';
        wrapper.innerHTML = '';
    });
    
    pdfContainer.style.transition = 'none';
    pdfContainer.style.transform = 'scale(1)';
    pdfContainer.style.transformOrigin = 'top center';
    
    requestAnimationFrame(function() {
        var newHeight = pdfScrollEl ? pdfScrollEl.scrollHeight : 0;
        if (scrollHeight > 0 && newHeight > 0) {
            pdfScrollEl.scrollTop = scrollTop * (newHeight / scrollHeight);
        }
        pdfRenderVisiblePages();
    });
}

function pdfUnrenderDistantPages() {
    if (!pdfScrollEl || !pdfContainer) return;
    
    var scrollTop = pdfScrollEl.scrollTop;
    var viewHeight = pdfScrollEl.clientHeight;
    var keepBuffer = 1200;
    
    var wrappers = pdfContainer.querySelectorAll('.pdf-page-wrapper');
    wrappers.forEach(function(wrapper) {
        var top = wrapper.offsetTop;
        var bottom = top + wrapper.offsetHeight;
        var num = parseInt(wrapper.getAttribute('data-page'));
        
        if (bottom < scrollTop - keepBuffer || top > scrollTop + viewHeight + keepBuffer) {
            if (pdfRenderedPages[num] && wrapper.querySelector('canvas')) {
                wrapper.innerHTML = '';
                pdfRenderedPages[num] = false;
            }
        }
    });
}

function initPdfGestures() {
    if (pdfHammer) {
        pdfHammer.destroy();
        pdfHammer = null;
    }
    
    if (!pdfScrollEl || typeof Hammer === 'undefined') return;
    
    pdfHammer = new Hammer(pdfScrollEl, {
        touchAction: 'pan-y pan-x',
        recognizers: [
            [Hammer.Pinch, { enable: true }],
            [Hammer.Tap, { event: 'doubletap', taps: 2 }]
        ]
    });
    
    pdfHammer.get('pinch').set({ enable: true });
    
    pdfHammer.on('pinchstart', function() {
        pdfTouchActive = true;
        pdfPinchStartScale = pdfScale;
        pdfContainer.style.transition = 'none';
        pdfScrollEl.style.touchAction = 'none';
    });
    
    pdfHammer.on('pinchmove', function(e) {
        if (!pdfTouchActive) return;
        var newScale = Math.min(Math.max(pdfPinchStartScale * e.scale, 0.5), 5);
        pdfApplyScale(newScale);
    });
    
    pdfHammer.on('pinchend', function(e) {
        pdfTouchActive = false;
        pdfScrollEl.style.touchAction = '';
        pdfContainer.style.transition = 'transform 0.1s ease-out';
        pdfScale = Math.min(Math.max(pdfPinchStartScale * e.scale, 0.5), 5);
        pdfApplyScale(pdfScale);
        updatePdfZoomLabel();
        pdfRerenderVisiblePages();
    });
    
    pdfHammer.on('doubletap', function(e) {
        pdfContainer.style.transition = 'transform 0.2s ease-out';
        
        if (Math.abs(pdfScale - pdfFitWidthScale) < 0.05) {
            var rect = pdfScrollEl.getBoundingClientRect();
            var tapX = e.center.x - rect.left;
            var tapY = e.center.y - rect.top + pdfScrollEl.scrollTop;
            pdfScale = pdfFitWidthScale * 2.5;
            pdfApplyScale(pdfScale, tapX, tapY);
        } else {
            pdfScale = pdfFitWidthScale;
            pdfApplyScale(pdfScale);
        }
        
        updatePdfZoomLabel();
        setTimeout(function() {
            pdfRerenderVisiblePages();
        }, 200);
    });
    
    pdfScrollEl.addEventListener('scroll', pdfOnScroll, { passive: true });
}

function pdfOnScroll() {
    if (pdfScrollTick) return;
    pdfScrollTick = true;
    requestAnimationFrame(function() {
        pdfScrollTick = false;
        pdfTrackCurrentPage();
        pdfRenderVisiblePages();
        pdfUnrenderDistantPages();
    });
}

function pdfApplyScale(newScale, originX, originY) {
    if (!pdfContainer) return;
    
    if (originX !== undefined && originY !== undefined) {
        var containerWidth = pdfContainer.scrollWidth;
        var containerHeight = pdfContainer.scrollHeight;
        var px = originX / containerWidth * 100;
        var py = originY / containerHeight * 100;
        pdfContainer.style.transformOrigin = px + '% ' + py + '%';
    } else {
        pdfContainer.style.transformOrigin = 'top center';
    }
    
    pdfContainer.style.transform = 'scale(' + newScale + ')';
}

function pdfGoPrev() {
    if (!pdfDoc || pdfCurrentPage <= 1) return;
    pdfScrollToPage(pdfCurrentPage - 1);
}

function pdfGoNext() {
    if (!pdfDoc || pdfCurrentPage >= pdfDoc.numPages) return;
    pdfScrollToPage(pdfCurrentPage + 1);
}

function pdfScrollToPage(num) {
    if (!pdfContainer || !pdfScrollEl) return;
    var wrapper = pdfContainer.querySelector('[data-page="' + num + '"]');
    if (wrapper) {
        pdfScrollEl.scrollTo({ top: wrapper.offsetTop - 8, behavior: 'smooth' });
    }
    pdfCurrentPage = num;
    updatePdfPageInfo();
}

function updatePdfPageInfo() {
    var el = document.getElementById('pdf-page-info');
    if (el) {
        var total = pdfDoc ? pdfDoc.numPages : 0;
        el.textContent = pdfCurrentPage + ' / ' + total;
    }
    updatePdfNavButtons();
}

function updatePdfNavButtons() {
    var prev = document.getElementById('pdf-prev');
    var next = document.getElementById('pdf-next');
    if (prev) prev.disabled = !pdfDoc || pdfCurrentPage <= 1;
    if (next) next.disabled = !pdfDoc || pdfCurrentPage >= (pdfDoc ? pdfDoc.numPages : 0);
}

function updatePdfZoomLabel() {
    var el = document.getElementById('pdf-zoom-label');
    if (el && pdfFitWidthScale > 0) {
        el.textContent = Math.round(pdfScale / pdfFitWidthScale * 100) + '%';
    }
}

function pdfZoomIn() {
    if (!pdfDoc) return;
    pdfScale = Math.min(pdfScale + pdfFitWidthScale * 0.1, 5);
    updatePdfZoomLabel();
    pdfRerenderVisiblePages();
}

function pdfZoomOut() {
    if (!pdfDoc) return;
    pdfScale = Math.max(pdfScale - pdfFitWidthScale * 0.1, 0.5);
    updatePdfZoomLabel();
    pdfRerenderVisiblePages();
}

function pdfFitWidth() {
    if (!pdfDoc) return;
    pdfScale = pdfFitWidthScale;
    updatePdfZoomLabel();
    pdfRerenderVisiblePages();
}

function pdfFitPage() {
    if (!pdfDoc) return;
    pdfDoc.getPage(pdfCurrentPage).then(function(page) {
        var viewport = page.getViewport({ scale: 1 });
        var scrollEl = document.getElementById('pdf-scroll');
        if (!scrollEl) return;
        var scaleW = (scrollEl.clientWidth - 32) / viewport.width;
        var scaleH = (scrollEl.clientHeight - 32) / viewport.height;
        pdfScale = Math.min(scaleW, scaleH);
        pdfFitWidthScale = scaleW;
        updatePdfZoomLabel();
        pdfRerenderVisiblePages();
    });
}

function pdfTrackCurrentPage() {
    if (!pdfScrollEl || !pdfContainer) return;
    
    var scrollTop = pdfScrollEl.scrollTop;
    var viewHeight = pdfScrollEl.clientHeight;
    var midPoint = scrollTop + viewHeight / 2;
    
    var wrappers = pdfContainer.querySelectorAll('.pdf-page-wrapper');
    var currentPage = 1;
    
    wrappers.forEach(function(wrapper) {
        if (wrapper.offsetTop <= midPoint) {
            currentPage = parseInt(wrapper.getAttribute('data-page'));
        }
    });
    
    if (currentPage !== pdfCurrentPage) {
        pdfCurrentPage = currentPage;
        updatePdfPageInfo();
    }
}

function closePdfViewer() {
    var overlay = document.getElementById('pdf-viewer');
    var loadingEl = document.getElementById('pdf-loading');
    
    if (overlay) {
        overlay.classList.remove('active');
    }
    
    if (loadingEl) {
        loadingEl.style.display = '';
        loadingEl.innerHTML = '<div class="pdf-spinner"></div><span>Cargando PDF...</span>';
    }
    
    if (pdfHammer) {
        pdfHammer.destroy();
        pdfHammer = null;
    }
    
    if (pdfVisibleObserver) {
        pdfVisibleObserver.disconnect();
        pdfVisibleObserver = null;
    }
    
    if (pdfScrollEl) {
        pdfScrollEl.removeEventListener('scroll', pdfOnScroll);
    }
    
    var container = document.getElementById('pdf-pages-container');
    if (container) container.remove();
    
    pdfDoc = null;
    pdfCurrentPage = 1;
    pdfScale = 1;
    pdfBaseScale = 1;
    pdfRendering = false;
    pdfContainer = null;
    pdfScrollEl = null;
    pdfPageDims = [];
    pdfRenderedPages = {};
    
    document.body.style.overflow = '';
    document.documentElement.style.overflow = '';
}
EOF
    
    log_success "JavaScript generado"
}

# Generar página principal (index.html)
generate_index() {
    log_info "Generando página principal..."
    
    local site_name
    site_name=$(read_config "site.name")
    local site_title
    site_title=$(read_config "site.title")
    local site_subtitle
    site_subtitle=$(read_config "site.subtitle")
    local site_description
    site_description=$(read_config "site.description")
    local site_url
    site_url=$(read_config "site.url")
    local site_email
    site_email=$(read_config "site.email")
    local site_github
    site_github=$(read_config "site.github")
    local footer_copyright
    footer_copyright=$(read_config "footer.copyright")
    
    # Leer configuración del catálogo
    local CATALOG_DESKTOP CATALOG_TABLET CATALOG_MOBILE
    CATALOG_DESKTOP=$(python3 -c "
import json
with open('${CONFIG_JSON}', 'r') as f:
    config = json.load(f)
cat = config.get('catalog', {}).get('booksPerPage', {})
print(cat.get('desktop', 8))
")
    CATALOG_TABLET=$(python3 -c "
import json
with open('${CONFIG_JSON}', 'r') as f:
    config = json.load(f)
cat = config.get('catalog', {}).get('booksPerPage', {})
print(cat.get('tablet', 6))
")
    CATALOG_MOBILE=$(python3 -c "
import json
with open('${CONFIG_JSON}', 'r') as f:
    config = json.load(f)
cat = config.get('catalog', {}).get('booksPerPage', {})
print(cat.get('mobile', 4))
")
    
    # Construir navegación según secciones habilitadas
    local nav_items=""
    if is_section_enabled "home"; then
        nav_items="${nav_items}                <a href=\"/\">Inicio</a>\n"
    fi
    if is_section_enabled "catalog"; then
        nav_items="${nav_items}                <a href=\"/catalog.html\">Catálogo</a>\n"
    fi
    if is_section_enabled "about"; then
        nav_items="${nav_items}                <a href=\"/about.html\">Acerca de</a>\n"
    fi
    if is_external_site_enabled; then
        local ext_url ext_title ext_newtab
        ext_url=$(read_external_site "url")
        ext_title=$(read_external_site "title")
        ext_newtab=$(read_external_site "newTab")
        if [ "$ext_newtab" = "true" ]; then
            nav_items="${nav_items}                <a href=\"${ext_url}\" target=\"_blank\" class=\"btn-nav-external\">${ext_title}</a>\n"
        else
            nav_items="${nav_items}                <a href=\"${ext_url}\" class=\"btn-nav-external\">${ext_title}</a>\n"
        fi
    fi
    
    # Construir enlaces del footer según secciones habilitadas
    local footer_links=""
    if is_section_enabled "home"; then
        footer_links="${footer_links}                <a href=\"/\">Inicio</a><br>\n"
    fi
    if is_section_enabled "catalog"; then
        footer_links="${footer_links}                <a href=\"/catalog.html\">Catálogo</a><br>\n"
    fi
    if is_section_enabled "about"; then
        footer_links="${footer_links}                <a href=\"/about.html\">Acerca de</a><br>\n"
    fi
    
    cat > "${PUBLIC_DIR}/index.html" << EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="${site_description}">
    <meta name="domain" content="${site_url}">
    <link rel="canonical" href="${site_url}/">
    <meta property="og:title" content="${site_name} | ${site_title}">
    <meta property="og:description" content="${site_description}">
    <meta property="og:url" content="${site_url}/">
    <meta property="og:type" content="website">
    <title>${site_name} | ${site_title}</title>
    <link rel="stylesheet" href="/css/styles.css">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
</head>
<body>
    <header class="header">
        <div class="header-content">
            <a href="/" class="logo">
                <svg class="logo-icon" viewBox="0 0 24 24">
                    <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/>
                </svg>
                <span class="logo-text">${site_name}</span>
            </a>
            <button class="menu-toggle" aria-label="Abrir menú" onclick="toggleMenu()">
                <svg viewBox="0 0 24 24">
                    <line x1="3" y1="6" x2="21" y2="6"/>
                    <line x1="3" y1="12" x2="21" y2="12"/>
                    <line x1="3" y1="18" x2="21" y2="18"/>
                </svg>
            </button>
            <nav class="nav" id="nav-menu">
$(echo -e "$nav_items")            </nav>
            <div class="nav-overlay" id="nav-overlay" onclick="closeMenu()"></div>
        </div>
    </header>

    <main class="container">
        <section class="hero">
            <h1>${site_title}</h1>
            <p>${site_subtitle}</p>
        </section>

        <section class="search-container">
            <div class="search-box">
                <svg class="search-icon" viewBox="0 0 24 24">
                    <circle cx="11" cy="11" r="8"/>
                    <path d="M21 21l-4.35-4.35"/>
                </svg>
                <input type="search" 
                       id="search-input" 
                       class="search-input" 
                       placeholder="Buscar por título, categoría o etiquetas..."
                       aria-label="Buscar libros">
            </div>
        </section>

        <div class="filter-bar">
            <button class="filter-toggle-btn" onclick="toggleFilters()">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/>
                </svg>
                Filtros
                <span class="filter-count-badge" id="filter-count"></span>
            </button>
            <button class="filter-clear-btn" id="filter-clear" onclick="clearAllFilters()">
                Limpiar filtros
            </button>
        </div>

        <div class="filter-panel" id="filter-panel">
            <div class="filter-group">
                <h4>Categorías</h4>
                <div class="filter-chips" id="filter-categories">%%FILTER_CATEGORIES%%</div>
            </div>
            <div class="filter-group">
                <h4>Etiquetas</h4>
                <div class="filter-chips" id="filter-tags">%%FILTER_TAGS%%</div>
            </div>
        </div>

        <section id="books-container" class="books-grid">
%%BOOK_CARDS%%
        </section>

        <nav class="pagination" id="pagination" aria-label="Paginación">
        </nav>
    </main>

    <footer class="footer">
        <div class="footer-content">
            <div class="footer-section">
                <h3>${site_name}</h3>
                <p>${site_description}</p>
            </div>
            <div class="footer-section">
                <h3>Enlaces</h3>
$(echo -e "$footer_links")            </div>
            <div class="footer-section">
                <h3>Contacto</h3>
$([ -n "$site_email" ] && echo "                <p>${site_email}</p>")
                <a href="${site_github}" target="_blank">GitHub</a>
            </div>
        </div>
        <div class="footer-bottom">
            <p>&copy; ${footer_copyright}. Todos los derechos reservados.</p>
        </div>
    </footer>

    <div class="pdf-viewer-overlay" id="pdf-viewer">
        <div class="pdf-viewer-header">
            <button class="pdf-viewer-close" onclick="closePdfViewer()" aria-label="Cerrar visor">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <line x1="18" y1="6" x2="6" y2="18"/>
                    <line x1="6" y1="6" x2="18" y2="18"/>
                </svg>
            </button>
            <span class="pdf-viewer-title" id="pdf-viewer-title"></span>
            <div class="pdf-viewer-toolbar">
                <button class="pdf-tool-btn" id="pdf-prev" onclick="pdfGoPrev()" aria-label="Página anterior" title="Anterior">
                    <svg viewBox="0 0 24 24" width="18" height="18"><path d="M15 18l-6-6 6-6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
                </button>
                <span class="pdf-page-info" id="pdf-page-info">1 / 1</span>
                <button class="pdf-tool-btn" id="pdf-next" onclick="pdfGoNext()" aria-label="Página siguiente" title="Siguiente">
                    <svg viewBox="0 0 24 24" width="18" height="18"><path d="M9 18l6-6-6-6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
                </button>
                <span class="pdf-toolbar-sep"></span>
                <button class="pdf-tool-btn" onclick="pdfZoomOut()" aria-label="Reducir" title="Zoom -">
                    <svg viewBox="0 0 24 24" width="18" height="18"><line x1="5" y1="12" x2="19" y2="12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
                </button>
                <span class="pdf-zoom-label" id="pdf-zoom-label">100%</span>
                <button class="pdf-tool-btn" onclick="pdfZoomIn()" aria-label="Ampliar" title="Zoom +">
                    <svg viewBox="0 0 24 24" width="18" height="18"><line x1="12" y1="5" x2="12" y2="19" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><line x1="5" y1="12" x2="19" y2="12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
                </button>
                <span class="pdf-toolbar-sep"></span>
                <button class="pdf-tool-btn" onclick="pdfFitWidth()" aria-label="Ajustar al ancho" title="Ajustar ancho">
                    <svg viewBox="0 0 24 24" width="18" height="18"><path d="M21 3H3v18h18V3zM9 3v18M15 3v18M3 9h18M3 15h18" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>
                </button>
                <button class="pdf-tool-btn" onclick="pdfFitPage()" aria-label="Ajustar a página" title="Ajustar página">
                    <svg viewBox="0 0 24 24" width="18" height="18"><rect x="4" y="2" width="16" height="20" rx="2" fill="none" stroke="currentColor" stroke-width="1.5"/><line x1="8" y1="6" x2="16" y2="6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="8" y1="10" x2="16" y2="10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/><line x1="8" y1="14" x2="13" y2="14" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>
                </button>
            </div>
        </div>
        <div class="pdf-viewer-body" id="pdf-viewer-body">
            <div class="pdf-viewer-loading" id="pdf-loading">
                <div class="pdf-spinner"></div>
                <span>Cargando PDF...</span>
            </div>
            <div class="pdf-viewer-scroll" id="pdf-scroll">
            </div>
        </div>
    </div>

    <script src="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js"></script>
    <script>
        if (typeof pdfjsLib !== 'undefined') {
            pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
        }
    </script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/hammer.js/2.0.8/hammer.min.js"></script>
    <script>
        window.CATALOG_CONFIG = {
            booksPerPage: {
                desktop: ${CATALOG_DESKTOP},
                tablet: ${CATALOG_TABLET},
                mobile: ${CATALOG_MOBILE}
            }
        };
    </script>
    <script src="/js/app.js"></script>
</body>
</html>
EOF
    
    # Reemplazar placeholders con HTML generado desde books.json
    python3 << 'PYEOF'
import json, os

books_json = os.environ.get('BOOKS_JSON', 'assets/information/books.json')
html_file = os.environ.get('PUBLIC_DIR', 'public') + '/index.html'

with open(books_json, 'r') as f:
    books = json.load(f)

cards = []
for b in books:
    tags = ','.join(b.get('tags', []))
    ext = b['cover'].rsplit('.', 1)[-1] if '.' in b['cover'] else 'webp'
    cover = b['cover'].replace('.' + ext, '.webp')
    t = b['title'].replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')
    title_js = b['title'].replace("'", "\\'").replace('"', '\\"')
    cards.append(
        '<article class="book-card" data-title="%s" data-category="%s" data-tags="%s">\n'
        '            <img src="/img/covers/%s" alt="Portada de %s" class="book-cover" loading="lazy">\n'
        '            <div class="book-info">\n'
        '                <span class="book-category">%s</span>\n'
        '                <h3 class="book-title">%s</h3>\n'
        '                <div class="book-meta">\n'
        '                    <span>%s páginas</span>\n'
        '                    <span>%s</span>\n'
        '                    <span>%s</span>\n'
        '                </div>\n'
        '                <div class="book-actions">\n'
        '                    <button type="button" class="btn btn-primary" onclick="openPdfViewer(\'/pdf/%s\', \'%s\')">Ver Libro</button>\n'
        '                    <a href="/pdf/%s" class="btn btn-secondary" download>Descargar</a>\n'
        '                </div>\n'
        '            </div>\n'
        '        </article>'
        % (t, b['category'], tags, cover, t, b['category'], t, b['pages'], b['year'], b['license'], b['file'], title_js, b['file'])
    )

cats = sorted(set(b['category'] for b in books))
cat_chips = []
for c in cats:
    ce = c.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')
    cat_chips.append(
        '<button class="filter-chip" data-category="%s" onclick="toggleCategory(\'%s\')">%s</button>'
        % (ce, c.replace("'", "\\'"), ce)
    )

tags = sorted(set(t for b in books for t in b.get('tags', [])))
tag_chips = []
for t in tags:
    te = t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')
    tag_chips.append(
        '<button class="filter-chip" data-tag="%s" onclick="toggleTag(\'%s\')">%s</button>'
        % (te, t.replace("'", "\\'"), te)
    )

with open(html_file, 'r') as f:
    html = f.read()

html = html.replace('%%BOOK_CARDS%%', '\n'.join(cards))
html = html.replace('%%FILTER_CATEGORIES%%', '\n'.join(cat_chips))
html = html.replace('%%FILTER_TAGS%%', '\n'.join(tag_chips))

with open(html_file, 'w') as f:
    f.write(html)
PYEOF
    
    log_success "Página principal generada"
}

# Generar página Acerca de
generate_about() {
    log_info "Generando página Acerca de..."
    
    local site_name
    site_name=$(read_config "site.name")
    local site_url
    site_url=$(read_config "site.url")
    local site_github
    site_github=$(read_config "site.github")
    local site_email
    site_email=$(read_config "site.email")
    local footer_copyright
    footer_copyright=$(read_config "footer.copyright")
    
    # Leer about.json
    local about_title
    about_title=$(python3 -c "
import json
with open('${ABOUT_JSON}', 'r') as f:
    data = json.load(f)
print(data.get('title', 'Acerca de'))
")
    local about_subtitle
    about_subtitle=$(python3 -c "
import json
with open('${ABOUT_JSON}', 'r') as f:
    data = json.load(f)
print(data.get('subtitle', ''))
")
    
    # Construir descripción (array de párrafos)
    local about_desc_html
    about_desc_html=$(python3 -c "
import json
with open('${ABOUT_JSON}', 'r') as f:
    data = json.load(f)
desc = data.get('description', [])
for p in desc:
    print('<p>' + p + '</p>')
")
    
    # Obtener misión
    local about_mission
    about_mission=$(python3 -c "
import json
with open('${ABOUT_JSON}', 'r') as f:
    data = json.load(f)
print(data.get('mission', ''))
")
    
    # Obtener visión
    local about_vision
    about_vision=$(python3 -c "
import json
with open('${ABOUT_JSON}', 'r') as f:
    data = json.load(f)
print(data.get('vision', ''))
")
    
    # Construir objetivos (lista)
    local about_objectives_html
    about_objectives_html=$(python3 -c "
import json
with open('${ABOUT_JSON}', 'r') as f:
    data = json.load(f)
objectives = data.get('objectives', [])
for obj in objectives:
    print('<li>' + obj + '</li>')
")
    
    # Construir navegación
    local nav_items=""
    if is_section_enabled "home"; then
        nav_items="${nav_items}                <a href=\"/\">Inicio</a>\n"
    fi
    if is_section_enabled "catalog"; then
        nav_items="${nav_items}                <a href=\"/catalog.html\">Catálogo</a>\n"
    fi
    if is_section_enabled "about"; then
        nav_items="${nav_items}                <a href=\"/about.html\">Acerca de</a>\n"
    fi
    if is_external_site_enabled; then
        local ext_url ext_title ext_newtab
        ext_url=$(read_external_site "url")
        ext_title=$(read_external_site "title")
        ext_newtab=$(read_external_site "newTab")
        if [ "$ext_newtab" = "true" ]; then
            nav_items="${nav_items}                <a href=\"${ext_url}\" target=\"_blank\" class=\"btn-nav-external\">${ext_title}</a>\n"
        else
            nav_items="${nav_items}                <a href=\"${ext_url}\" class=\"btn-nav-external\">${ext_title}</a>\n"
        fi
    fi
    
    # Construir enlaces del footer
    local footer_links=""
    if is_section_enabled "home"; then
        footer_links="${footer_links}                <a href=\"/\">Inicio</a><br>\n"
    fi
    if is_section_enabled "catalog"; then
        footer_links="${footer_links}                <a href=\"/catalog.html\">Catálogo</a><br>\n"
    fi
    if is_section_enabled "about"; then
        footer_links="${footer_links}                <a href=\"/about.html\">Acerca de</a><br>\n"
    fi
    
    cat > "${PUBLIC_DIR}/about.html" << EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="${about_subtitle}">
    <link rel="canonical" href="${site_url}/about.html">
    <title>${about_title} | ${site_name}</title>
    <link rel="stylesheet" href="/css/styles.css">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
</head>
<body>
    <header class="header">
        <div class="header-content">
            <a href="/" class="logo">
                <svg class="logo-icon" viewBox="0 0 24 24">
                    <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/>
                </svg>
                <span class="logo-text">${site_name}</span>
            </a>
            <button class="menu-toggle" aria-label="Abrir menú" onclick="toggleMenu()">
                <svg viewBox="0 0 24 24">
                    <line x1="3" y1="6" x2="21" y2="6"/>
                    <line x1="3" y1="12" x2="21" y2="12"/>
                    <line x1="3" y1="18" x2="21" y2="18"/>
                </svg>
            </button>
            <nav class="nav" id="nav-menu">
$(echo -e "$nav_items")            </nav>
            <div class="nav-overlay" id="nav-overlay" onclick="closeMenu()"></div>
        </div>
    </header>

    <main class="container">
        <section class="hero">
            <h1>${about_title}</h1>
            <p>${about_subtitle}</p>
        </section>

        <section class="about-content">
            <div class="about-section">
                $(echo "$about_desc_html")
            </div>

            <div class="about-section">
                <h2>Misión</h2>
                <p>${about_mission}</p>
            </div>

            <div class="about-section">
                <h2>Visión</h2>
                <p>${about_vision}</p>
            </div>

            <div class="about-section">
                <h2>Objetivos</h2>
                <ul>
$(echo -e "$about_objectives_html")                </ul>
            </div>
        </section>
    </main>

    <footer class="footer">
        <div class="footer-content">
            <div class="footer-section">
                <h3>${site_name}</h3>
                <p>${about_subtitle}</p>
            </div>
            <div class="footer-section">
                <h3>Enlaces</h3>
$(echo -e "$footer_links")            </div>
            <div class="footer-section">
                <h3>Contacto</h3>
$([ -n "$site_email" ] && echo "                <p>${site_email}</p>")
                <a href="${site_github}" target="_blank">GitHub</a>
            </div>
        </div>
        <div class="footer-bottom">
            <p>&copy; ${footer_copyright}. Todos los derechos reservados.</p>
        </div>
    </footer>

    <script src="/js/app.js"></script>
</body>
</html>
EOF
    
    log_success "Página Acerca de generada"
}

#===============================================================================
# FUNCIONES DE VALIDACIÓN
#===============================================================================

# Validar estructura de assets
validate_assets() {
    log_info "Validando estructura de assets..."
    
    local errors=0
    
    # Verificar books.json
    if ! python3 -c "import json; json.load(open('${BOOKS_JSON}'))" 2>/dev/null; then
        log_error "Error en formato de books.json"
        ((errors++))
    fi
    
    # Verificar config.json
    if ! python3 -c "import json; json.load(open('${CONFIG_JSON}'))" 2>/dev/null; then
        log_error "Error en formato de config.json"
        ((errors++))
    fi
    
    # Verificar members.json
    if ! python3 -c "import json; json.load(open('${MEMBERS_JSON}'))" 2>/dev/null; then
        log_error "Error en formato de members.json"
        ((errors++))
    fi
    
    # Verificar categories.json
    if ! python3 -c "import json; json.load(open('${CATEGORIES_JSON}'))" 2>/dev/null; then
        log_error "Error en formato de categories.json"
        ((errors++))
    fi
    
    # Verificar tags.json
    if ! python3 -c "import json; json.load(open('${TAGS_JSON}'))" 2>/dev/null; then
        log_error "Error en formato de tags.json"
        ((errors++))
    fi
    
    # Verificar about.json
    if ! python3 -c "import json; json.load(open('${ABOUT_JSON}'))" 2>/dev/null; then
        log_error "Error en formato de about.json"
        ((errors++))
    fi
    
    # Verificar themes.json
    if ! python3 -c "import json; json.load(open('${THEMES_JSON}'))" 2>/dev/null; then
        log_error "Error en formato de themes.json"
        ((errors++))
    fi
    
    if [ $errors -gt 0 ]; then
        log_error "Se encontraron $errors errores en la validación"
        exit 1
    fi
    
    log_success "Validación completada exitosamente"
}

#===============================================================================
# FUNCIÓN PRINCIPAL
#===============================================================================

main() {
    # Procesar argumentos de línea de comandos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --dev|-d)
                DEV_MODE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Opción desconocida: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo ""
    echo "========================================"
    echo "  Generador de Sitio Estático"
    echo "  Biblioteca - Núcleo Linux UAGRM"
    echo "========================================"
    echo ""
    
    # Verificar dependencias
    check_dependencies
    
    # Verificar soporte WEBP
    check_webp_support
    
    # Verificar archivos requeridos
    check_required_files
    
    # Validar assets
    validate_assets
    
    # Limpiar y crear estructura
    clean_public
    create_structure
    
    # Generar contenido
    generate_css
    generate_js
    generate_index
    
    # Generar páginas según secciones habilitadas
    if is_section_enabled "about"; then
        generate_about
    fi
    
    # Copiar assets estáticos
    copy_static_assets
    
    # Generar CNAME si está configurado
    if [ -n "${CNAME_DOMAIN:-}" ]; then
        echo -n "${CNAME_DOMAIN}" > "${PUBLIC_DIR}/CNAME"
        log_info "CNAME generado: ${CNAME_DOMAIN}"
    fi
    
    echo ""
    echo "========================================"
    log_success "¡Sitio generado exitosamente!"
    echo "========================================"
    echo ""
    echo "El sitio está disponible en: ${PUBLIC_DIR}/"
    echo ""
}

# Ejecutar función principal
main "$@"
