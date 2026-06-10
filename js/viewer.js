/**
 * SIENA Flood Maps viewer.
 * geotiff mode: viewport-scoped GeoTIFF loading (memory-capped).
 * tiles mode: pre-baked PNG tiles — low memory, best for 50+ granules/day.
 */
(function () {
  const config = window.FLOOD_VIEWER_CONFIG || {};
  const MODE = config.mode || "geotiff";
  const DATA_ROOT = config.dataRoot || "data/geotiffs/";
  const TILE_MIN_ZOOM = config.tileMinZoom ?? 3;
  const TILE_MAX_ZOOM = config.tileMaxZoom ?? 10;
  const COVERAGE_ZOOM_UNTIL = config.coverageZoomUntil ?? 6;
  const MAP_MIN_ZOOM = 3;
  const MAP_MAX_ZOOM = 12;
  const MAX_CONCURRENT = config.maxConcurrent || 3;
  const GEORASTER_CACHE_MAX = config.georasterCacheMax || 6;
  const MAX_OVERLAYS_IN_VIEW = config.maxOverlaysInView || 6;
  const MIN_ZOOM_TO_LOAD = config.minZoomToLoad ?? 7;
  const MOVE_DEBOUNCE_MS = config.moveDebounceMs || 250;
  const isTiles = MODE === "tiles";

  const CLASS_COLORS = {
    1: [0, 92, 230],
    3: [219, 0, 0],
  };

  const dateSelect = document.getElementById("date-select");
  const opacityInput = document.getElementById("opacity");
  const statusEl = document.getElementById("status");
  const infoEl = document.getElementById("granule-info");
  const zoomSlider = document.getElementById("zoom-slider");
  const zoomValue = document.getElementById("zoom-value");
  const zoomHint = document.getElementById("zoom-hint");
  const scaleBarLine = document.getElementById("scale-bar-line");
  const scaleBarLabel = document.getElementById("scale-bar-label");

  const INVISIBLE_HIT_STYLE = {
    color: "transparent",
    fillColor: "transparent",
    fillOpacity: 0,
    opacity: 0,
    weight: 0,
    interactive: true,
  };

  const COVERAGE_STYLE = {
    color: "#0b5cab",
    weight: 1.5,
    fillColor: "#5c9ded",
    fillOpacity: 0.22,
    opacity: 0.85,
    interactive: false,
  };

  let catalog = null;
  let map = null;
  let currentDate = null;
  let overlayById = new Map();
  let hitById = new Map();
  let coverageById = new Map();
  let zoomSliderSyncing = false;
  let georasterCache = new Map();
  let georasterCacheOrder = [];
  let syncToken = 0;
  let moveDebounceTimer = null;
  let syncInFlight = false;
  let syncQueued = false;

  function setStatus(message) {
    statusEl.textContent = message;
  }

  function formatUtc(isoString) {
    if (!isoString) return "—";
    return new Date(isoString).toISOString().replace("T", " ").replace(".000Z", " UTC");
  }

  function formatDateLabel(yyyymmdd) {
    return `${yyyymmdd.slice(0, 4)}-${yyyymmdd.slice(4, 6)}-${yyyymmdd.slice(6, 8)}`;
  }

  function satelliteId(filename) {
    const match = filename.match(/_(S1[ABCD])_/);
    return match ? match[1] : "Unknown";
  }

  function boundsFromProduct(product) {
    const [west, south, east, north] = product.bounds;
    return L.latLngBounds([south, west], [north, east]);
  }

  function productInView(product) {
    return map.getBounds().intersects(boundsFromProduct(product));
  }

  function productsForDate(date) {
    return catalog.products.filter((p) => p.sensing_date === date);
  }

  function granuleInfoHtml(product) {
    return `
      <div class="popup-title">${satelliteId(product.filename)} granule</div>
      <div><strong>Start:</strong> ${formatUtc(product.sensing_start)}</div>
      <div><strong>End:</strong> ${formatUtc(product.sensing_end)}</div>
      <div><strong>File:</strong><br><span class="mono">${product.filename}</span></div>
    `;
  }

  function showInfoPanel(product) {
    infoEl.innerHTML = `
      <p class="info-hint">Click anywhere on a granule on the map for details.</p>
      <div class="info-card">
        <h3>${satelliteId(product.filename)} · ${formatUtc(product.sensing_start)}</h3>
        <dl>
          <dt>Sensing end</dt><dd>${formatUtc(product.sensing_end)}</dd>
          <dt>Date</dt><dd>${formatDateLabel(product.sensing_date)}</dd>
          <dt>Bounds (W,S,E,N)</dt>
          <dd class="mono">${product.bounds.map((v) => v.toFixed(4)).join(", ")}</dd>
          <dt>Filename</dt><dd class="mono">${product.filename}</dd>
        </dl>
      </div>
    `;
  }

  function pixelColor(values, opacity) {
    const value = Math.round(values[0]);
    if (value === 255 || value === 0) return "rgba(0,0,0,0)";
    const rgb = CLASS_COLORS[value];
    if (!rgb) return "rgba(0,0,0,0)";
    return `rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${opacity})`;
  }

  function renderResolution() {
    const zoom = map.getZoom();
    if (zoom >= 10) return 128;
    if (zoom >= 8) return 96;
    return 64;
  }

  function touchGeorasterCache(productId) {
    const index = georasterCacheOrder.indexOf(productId);
    if (index >= 0) georasterCacheOrder.splice(index, 1);
    georasterCacheOrder.push(productId);
  }

  function evictGeoraster(productId) {
    georasterCache.delete(productId);
    const index = georasterCacheOrder.indexOf(productId);
    if (index >= 0) georasterCacheOrder.splice(index, 1);
  }

  function trimGeorasterCache() {
    while (georasterCacheOrder.length > GEORASTER_CACHE_MAX) {
      const oldest = georasterCacheOrder.shift();
      georasterCache.delete(oldest);
      if (overlayById.has(oldest)) {
        const layer = overlayById.get(oldest);
        map.removeLayer(layer);
        overlayById.delete(oldest);
      }
    }
  }

  function clearGeorasterCache() {
    georasterCache.clear();
    georasterCacheOrder.length = 0;
  }

  function clearViewportLayers() {
    overlayById.forEach((layer) => map.removeLayer(layer));
    hitById.forEach((layer) => map.removeLayer(layer));
    coverageById.forEach((layer) => map.removeLayer(layer));
    overlayById.clear();
    hitById.clear();
    coverageById.clear();
  }

  function removeOverlay(productId) {
    const layer = overlayById.get(productId);
    if (layer) {
      map.removeLayer(layer);
      overlayById.delete(productId);
    }
    const hit = hitById.get(productId);
    if (hit) {
      map.removeLayer(hit);
      hitById.delete(productId);
    }
    if (MODE !== "tiles") {
      evictGeoraster(productId);
    }
  }

  function ensureHitArea(product) {
    if (hitById.has(product.id)) return;
    const hitArea = L.rectangle(boundsFromProduct(product), INVISIBLE_HIT_STYLE).addTo(map);
    hitArea.bindPopup(granuleInfoHtml(product), { maxWidth: 360 });
    hitArea.on("click", (event) => {
      L.DomEvent.stopPropagation(event);
      showInfoPanel(product);
      hitArea.openPopup();
    });
    hitById.set(product.id, hitArea);
  }

  function tileUrl(productId) {
    return `tiles/${encodeURIComponent(productId)}/{z}/{x}/{y}.png`;
  }

  async function getGeoraster(product) {
    if (georasterCache.has(product.id)) {
      touchGeorasterCache(product.id);
      return georasterCache.get(product.id);
    }
    const url = new URL(`${DATA_ROOT}${product.filename}`, document.baseURI).href;
    const georaster = await parseGeoraster(url);
    georasterCache.set(product.id, georaster);
    touchGeorasterCache(product.id);
    trimGeorasterCache();
    return georaster;
  }

  async function addGeotiffOverlay(product, opacity) {
    if (typeof parseGeoraster !== "function" || typeof GeoRasterLayer !== "function") {
      throw new Error("georaster libraries not loaded");
    }
    const georaster = await getGeoraster(product);
    const layer = new GeoRasterLayer({
      georaster,
      opacity,
      resolution: renderResolution(),
      pixelValuesToColorFn(values) {
        return pixelColor(values, opacity);
      },
    });
    layer.addTo(map);
    return layer;
  }

  function addTileOverlay(product, opacity) {
    return L.tileLayer(tileUrl(product.id), {
      minZoom: TILE_MIN_ZOOM,
      maxZoom: MAP_MAX_ZOOM,
      maxNativeZoom: TILE_MAX_ZOOM,
      opacity,
      bounds: boundsFromProduct(product),
    }).addTo(map);
  }

  function buildCoverageLayers(products) {
    products.forEach((product) => {
      const layer = L.rectangle(boundsFromProduct(product), COVERAGE_STYLE);
      coverageById.set(product.id, layer);
    });
    updateCoverageVisibility();
  }

  function updateCoverageVisibility() {
    if (!isTiles || !map) return;
    const showCoverage = map.getZoom() < COVERAGE_ZOOM_UNTIL;
    coverageById.forEach((layer) => {
      if (showCoverage) {
        if (!map.hasLayer(layer)) layer.addTo(map);
      } else if (map.hasLayer(layer)) {
        map.removeLayer(layer);
      }
    });
    if (zoomHint) {
      zoomHint.textContent = showCoverage
        ? "Blue outlines show granule coverage — zoom in for flood detail."
        : "Flood classification tiles active — use zoom slider to step in or out.";
    }
  }

  function formatScaleDistance(meters) {
    if (meters >= 1000) {
      const km = meters / 1000;
      return `${km >= 10 ? Math.round(km) : km.toFixed(1)} km`;
    }
    return `${Math.round(meters)} m`;
  }

  function updateScaleBar() {
    if (!map || !scaleBarLine || !scaleBarLabel) return;
    const centerLat = map.getCenter().lat;
    const metersPerPixel =
      (156543.03392 * Math.cos((centerLat * Math.PI) / 180)) / Math.pow(2, map.getZoom());
    const maxBarPx = 120;
    let meters = metersPerPixel * maxBarPx;
    const magnitude = Math.pow(10, Math.floor(Math.log10(meters)));
    const normalized = meters / magnitude;
    let nice = magnitude;
    if (normalized >= 5) nice = 5 * magnitude;
    else if (normalized >= 2) nice = 2 * magnitude;
    else nice = magnitude;
    const barPx = Math.max(36, Math.min(maxBarPx, nice / metersPerPixel));
    scaleBarLine.style.width = `${barPx}px`;
    scaleBarLabel.textContent = formatScaleDistance(nice);
  }

  function updateZoomControls() {
    if (!map || !zoomSlider || !zoomValue) return;
    const zoom = map.getZoom();
    zoomValue.textContent = String(zoom);
    if (!zoomSliderSyncing) {
      zoomSlider.value = String(Math.min(MAP_MAX_ZOOM, Math.max(MAP_MIN_ZOOM, zoom)));
    }
    updateScaleBar();
    updateCoverageVisibility();
  }

  function bindZoomControls() {
    if (!zoomSlider) return;
    zoomSlider.min = String(MAP_MIN_ZOOM);
    zoomSlider.max = String(MAP_MAX_ZOOM);
    zoomSlider.addEventListener("input", () => {
      zoomSliderSyncing = true;
      map.setZoom(Number(zoomSlider.value));
      zoomSliderSyncing = false;
      updateZoomControls();
    });
    map.on("zoomend", updateZoomControls);
    map.on("moveend", updateScaleBar);
    updateZoomControls();
  }

  async function loadProductOverlay(product, opacity, token) {
    const layer =
      MODE === "tiles"
        ? addTileOverlay(product, opacity)
        : await addGeotiffOverlay(product, opacity);
    if (token !== syncToken) {
      map.removeLayer(layer);
      return null;
    }
    overlayById.set(product.id, layer);
    ensureHitArea(product);
    return layer;
  }

  async function runPool(products, worker, limit) {
    let index = 0;
    async function workerLoop() {
      while (index < products.length) {
        const product = products[index];
        index += 1;
        await worker(product);
      }
    }
    const workers = Array.from({ length: Math.min(limit, products.length) }, () => workerLoop());
    await Promise.all(workers);
  }

  function prioritizedVisibleProducts(allProducts) {
    const center = map.getCenter();
    return allProducts
      .filter(productInView)
      .map((product) => ({
        product,
        dist: center.distanceTo(boundsFromProduct(product).getCenter()),
      }))
      .sort((a, b) => a.dist - b.dist)
      .map((entry) => entry.product);
  }

  function displayAllTileLayers(products) {
    const opacity = Number(opacityInput.value);
    buildCoverageLayers(products);
    products.forEach((product) => {
      const layer = addTileOverlay(product, opacity);
      overlayById.set(product.id, layer);
      ensureHitArea(product);
    });
    hitById.forEach((layer) => layer.bringToFront());
    updateCoverageVisibility();
    setStatus(
      `${formatDateLabel(currentDate)}: ${products.length} granule(s) — pan/zoom to explore`
    );
  }

  function updateStatusCounts(allProducts, visibleProducts, activeProducts) {
    const shown = overlayById.size;
    const active = activeProducts.length;
    const inView = visibleProducts.length;
    if (!isTiles && map.getZoom() < MIN_ZOOM_TO_LOAD) {
      setStatus(
        `Zoom in (level ${MIN_ZOOM_TO_LOAD}+) to load overlays · ${allProducts.length} granules`
      );
      return;
    }
    if (inView > active) {
      setStatus(
        `${formatDateLabel(currentDate)}: ${shown}/${active} shown · ${inView} in view · ${allProducts.length} total — pan to load more`
      );
      return;
    }
    setStatus(
      `${formatDateLabel(currentDate)}: ${shown}/${inView} in view · ${allProducts.length} total`
    );
  }

  async function syncOverlays() {
    if (!currentDate || !map) return;

    const token = ++syncToken;
    const opacity = Number(opacityInput.value);
    const allProducts = productsForDate(currentDate);

    if (!isTiles && map.getZoom() < MIN_ZOOM_TO_LOAD) {
      overlayById.forEach((_, productId) => removeOverlay(productId));
      updateStatusCounts(allProducts, [], []);
      return;
    }

    const visibleProducts = allProducts.filter(productInView);
    const activeProducts = prioritizedVisibleProducts(allProducts).slice(0, MAX_OVERLAYS_IN_VIEW);
    const activeIds = new Set(activeProducts.map((p) => p.id));

    overlayById.forEach((_, productId) => {
      if (!activeIds.has(productId)) removeOverlay(productId);
    });

    const pending = activeProducts.filter((product) => !overlayById.has(product.id));
    if (pending.length) {
      updateStatusCounts(allProducts, visibleProducts, activeProducts);
      await runPool(
        pending,
        async (product) => {
          if (token !== syncToken) return;
          try {
            await loadProductOverlay(product, opacity, token);
            if (token === syncToken) {
              updateStatusCounts(allProducts, visibleProducts, activeProducts);
            }
          } catch (error) {
            console.error(error);
            if (token === syncToken) {
              setStatus(`Failed: ${product.filename} — ${error.message}`);
            }
          }
        },
        MAX_CONCURRENT
      );
    }

    if (token !== syncToken) return;

    hitById.forEach((layer) => layer.bringToFront());
    updateStatusCounts(allProducts, visibleProducts, activeProducts);
  }

  function queueSyncOverlays() {
    if (syncInFlight) {
      syncQueued = true;
      return;
    }
    syncInFlight = true;
    syncOverlays()
      .catch((error) => {
        console.error(error);
        setStatus(`Overlay sync failed: ${error.message}`);
      })
      .finally(() => {
        syncInFlight = false;
        if (syncQueued) {
          syncQueued = false;
          queueSyncOverlays();
        }
      });
  }

  function scheduleSyncOverlays() {
    if (moveDebounceTimer) clearTimeout(moveDebounceTimer);
    moveDebounceTimer = setTimeout(() => {
      moveDebounceTimer = null;
      queueSyncOverlays();
    }, MOVE_DEBOUNCE_MS);
  }

  function displayDate(date) {
    currentDate = date;
    syncToken += 1;
    clearViewportLayers();
    clearGeorasterCache();

    const products = productsForDate(date);
    if (!products.length) {
      setStatus("No granules for this date.");
      infoEl.innerHTML = "<p>No data for selected date.</p>";
      return;
    }

    const groupBounds = L.latLngBounds([]);
    products.forEach((product) => groupBounds.extend(boundsFromProduct(product)));

    if (groupBounds.isValid()) {
      map.fitBounds(groupBounds, { padding: [30, 30], maxZoom: 8 });
    }
    showInfoPanel(products[0]);
    if (isTiles) {
      displayAllTileLayers(products);
    } else {
      queueSyncOverlays();
    }
  }

  function defaultSensingDate() {
    const dates = catalog.available_dates;
    return dates.length ? dates[dates.length - 1] : null;
  }

  function populateDateSelect() {
    const initialDate = defaultSensingDate();
    dateSelect.innerHTML = "";
    catalog.available_dates.forEach((date) => {
      const option = document.createElement("option");
      option.value = date;
      const count = productsForDate(date).length;
      option.textContent = `${formatDateLabel(date)} (${count} granule${count === 1 ? "" : "s"})`;
      if (date === initialDate) option.selected = true;
      dateSelect.appendChild(option);
    });
    if (initialDate) displayDate(initialDate);
  }

  function initMapView() {
    if (!catalog.products.length) {
      map.setView([40, -120], 4);
      return;
    }
    const [west, south, east, north] = catalog.products[0].bounds;
    map.setView([(south + north) / 2, (west + east) / 2], 5);
  }

  function loadCatalog() {
    if (window.FLOOD_CATALOG) {
      return Promise.resolve(window.FLOOD_CATALOG);
    }
    const url = new URL("data/catalog.json", document.baseURI).href;
    return fetch(url).then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return response.json();
    });
  }

  function boot() {
    if (typeof L === "undefined") {
      setStatus("Leaflet failed to load. Check your network connection.");
      return;
    }

    map = L.map("map", { zoomControl: true, minZoom: MAP_MIN_ZOOM, maxZoom: MAP_MAX_ZOOM });
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19,
    }).addTo(map);
    map.setView([30, -95], 4);
    bindZoomControls();
    if (!isTiles) {
      map.on("moveend", scheduleSyncOverlays);
      map.on("zoomend", scheduleSyncOverlays);
    }

    setStatus("Loading catalog…");
    loadCatalog()
      .then((data) => {
        catalog = data;
        initMapView();
        populateDateSelect();
      })
      .catch((error) => {
        setStatus(`Catalog failed to load: ${error.message}`);
      });
  }

  dateSelect.addEventListener("change", () => displayDate(dateSelect.value));

  opacityInput.addEventListener("input", () => {
    const opacity = Number(opacityInput.value);
    overlayById.forEach((layer) => layer.setOpacity(opacity));
  });

  boot();
})();
