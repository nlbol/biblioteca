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
    syncHeaderOffset();
    let resizeTimer;
    window.addEventListener('resize', () => {
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(() => {
            syncHeaderOffset();
            renderPage(false);
        }, 200);
    });
});

function syncHeaderOffset() {
    const header = document.querySelector('.header');
    const main = document.querySelector('.container');
    if (header && main) {
        main.style.paddingTop = header.offsetHeight + 'px';
    }
}

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
function renderPage(animate) {
    const container = document.getElementById('books-container');
    if (!container) return;
    
    const perPage = getBooksPerPage();
    const totalPages = Math.ceil(filteredCards.length / perPage);
    
    if (currentPage > totalPages) currentPage = totalPages || 1;
    
    const start = (currentPage - 1) * perPage;
    
    const doRender = () => {
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
        
        if (animate !== false) {
            requestAnimationFrame(() => {
                container.style.opacity = '1';
            });
        } else {
            container.style.opacity = '1';
        }
    };
    
    if (animate !== false) {
        container.style.opacity = '0';
        setTimeout(doRender, 150);
    } else {
        doRender();
    }
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
    pdfContainer = null;
    pdfScrollEl = null;
    pdfPageDims = [];
    pdfRenderedPages = {};
    
    document.body.style.overflow = '';
    document.documentElement.style.overflow = '';
}
