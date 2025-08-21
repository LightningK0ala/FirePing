// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
// Leaflet and MessagePack will be loaded from CDN

// Auto-dismiss flash messages
let Hooks = {};
// Simple dark-mode toggle: persists in localStorage and toggles `dark` on <html>
function applyTheme(theme) {
  const root = document.documentElement;
  if (theme === "dark") root.classList.add("dark");
  else root.classList.remove("dark");
}

function initTheme() {
  const saved = localStorage.getItem("fireping:theme");
  const theme =
    saved ||
    (window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light");
  applyTheme(theme);
  return theme;
}

let currentTheme = initTheme();
window.firepingToggleTheme = function () {
  currentTheme = currentTheme === "dark" ? "light" : "dark";
  localStorage.setItem("fireping:theme", currentTheme);
  applyTheme(currentTheme);
};

Hooks.ThemeToggle = {
  mounted() {
    this.el.addEventListener("click", () => {
      currentTheme = currentTheme === "dark" ? "light" : "dark";
      localStorage.setItem("fireping:theme", currentTheme);
      applyTheme(currentTheme);
    });
  },
};

Hooks.RadiusPreview = {
  mounted() {
    const notify = () =>
      window.dispatchEvent(new CustomEvent("fireping:update-draft"));
    this.el.addEventListener("input", notify);
    this.el.addEventListener("change", notify);
  },
};

Hooks.Flash = {
  mounted() {
    const flash = this.el;
    if (flash.dataset.autoDismiss === "true") {
      setTimeout(() => {
        flash.style.transition = "opacity 0.5s ease-out";
        flash.style.opacity = "0";
        setTimeout(() => {
          if (flash.parentNode) {
            flash.parentNode.removeChild(flash);
          }
        }, 500);
      }, 4000); // Auto-dismiss after 4 seconds
    }
  },
};

Hooks.Geolocation = {
  mounted() {
    const useLocationBtn = this.el;

    useLocationBtn.addEventListener("click", function () {
      if (!navigator.geolocation) {
        alert("Geolocation is not supported by this browser.");
        return;
      }

      const latInput = document.getElementById("latitude-input");
      const lngInput = document.getElementById("longitude-input");

      // Show loading state
      useLocationBtn.textContent = "🔄 Getting location...";
      useLocationBtn.disabled = true;

      navigator.geolocation.getCurrentPosition(
        function (position) {
          latInput.value = position.coords.latitude.toFixed(6);
          lngInput.value = position.coords.longitude.toFixed(6);

          // Reset button
          useLocationBtn.textContent = "📍 Use My Location";
          useLocationBtn.disabled = false;
        },
        function (error) {
          let message = "Unable to get your location. ";
          switch (error.code) {
            case error.PERMISSION_DENIED:
              message += "Please enable location access.";
              break;
            case error.POSITION_UNAVAILABLE:
              message += "Location information unavailable.";
              break;
            case error.TIMEOUT:
              message += "Location request timed out.";
              break;
            default:
              message += "An unknown error occurred.";
              break;
          }
          alert(message);

          // Reset button
          useLocationBtn.textContent = "📍 Use My Location";
          useLocationBtn.disabled = false;
        },
        {
          enableHighAccuracy: true,
          timeout: 10000,
          maximumAge: 0,
        }
      );
    });
  },
};

Hooks.Map = {
  mounted() {
    // Fix leaflet marker icon paths
    delete L.Icon.Default.prototype._getIconUrl;
    L.Icon.Default.mergeOptions({
      iconRetinaUrl:
        "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon-2x.png",
      iconUrl:
        "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon.png",
      shadowUrl:
        "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png",
    });

    // Initialize map centered on San Francisco
    this.map = L.map(this.el, {
      scrollWheelZoom: false,
      gestureHandling: true,
    }).setView([37.7749, -122.4194], 8);

    // Add OpenStreetMap tile layer
    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: "© OpenStreetMap contributors",
    }).addTo(this.map);

    // Handle map data updates from LiveView
    this.handleEvent("update_map_data", (data) => {
      const { locations, fires, fires_msgpack, fires_count } = data;

      let processedFires = fires;

      // If we have MessagePack fires data, decode it
      if (fires_msgpack && window.MessagePack) {
        try {
          // Decode base64 then MessagePack
          const binaryData = Uint8Array.from(atob(fires_msgpack), (c) =>
            c.charCodeAt(0)
          );
          const decodedData = window.MessagePack.decode(binaryData);

          // Convert compact array format back to objects
          processedFires = this.convertCompactFiresToObjects(decodedData);

          console.log(
            `🔥 Decoded ${processedFires.length} fires from MessagePack (${
              binaryData.length
            } bytes vs ~${
              JSON.stringify(processedFires).length
            } bytes uncompressed)`
          );
        } catch (error) {
          console.error("Failed to decode MessagePack fires data:", error);
          // Fallback to regular fires data if available
          processedFires = fires || [];
        }
      } else if (fires_msgpack && !window.MessagePack) {
        console.warn(
          "MessagePack library not loaded, falling back to regular fires data"
        );
        processedFires = fires || [];
      }

      this.updateMapData(locations, processedFires);
    });

    // Initialize with empty locations and fire cluster
    this.markersLayer = L.layerGroup().addTo(this.map);
    this.fireCluster = L.markerClusterGroup({
      maxClusterRadius: 50,
      spiderfyOnMaxZoom: true,
      showCoverageOnHover: false,
      zoomToBoundsOnClick: true,
      iconCreateFunction: (cluster) => this.createFireClusterIcon(cluster),
    }).addTo(this.map);

    // Listen for draft update requests (from slider or external triggers)
    window.addEventListener("fireping:update-draft", () =>
      this.updateDraftCircle()
    );

    // Also update draft when form inputs change (create form)
    const latInputEl = document.getElementById("latitude-input");
    const lngInputEl = document.getElementById("longitude-input");
    const radiusInputEl = document.getElementById("radius-input");
    const radiusNumberEl = document.getElementById("radius-number");
    const onChange = () => this.updateDraftCircle();
    if (latInputEl) {
      latInputEl.addEventListener("input", onChange);
      latInputEl.addEventListener("change", onChange);
    }
    if (lngInputEl) {
      lngInputEl.addEventListener("input", onChange);
      lngInputEl.addEventListener("change", onChange);
    }
    const syncRadius = () => {
      if (radiusInputEl && radiusNumberEl) {
        // slider is meters, number is km
        radiusNumberEl.value = String(
          Math.round(Number(radiusInputEl.value || 0) / 1000)
        );
      }
      this.updateDraftCircle();
    };
    if (radiusInputEl) {
      radiusInputEl.addEventListener("input", syncRadius);
      radiusInputEl.addEventListener("change", syncRadius);
    }
    if (radiusNumberEl) {
      radiusNumberEl.addEventListener("input", () => {
        if (radiusInputEl)
          radiusInputEl.value = String(
            Number(radiusNumberEl.value || 0) * 1000
          );
        this.updateDraftCircle();
      });
      radiusNumberEl.addEventListener("change", () => {
        if (radiusInputEl)
          radiusInputEl.value = String(
            Number(radiusNumberEl.value || 0) * 1000
          );
        this.updateDraftCircle();
      });
    }

    // Attach listeners for edit form when present
    this.currentEditingId = null;
    this.attachEditListeners = () => {
      const eid = this.getEditingId();
      if (!eid || eid === this.currentEditingId) return;
      this.currentEditingId = eid;

      const eLat = document.getElementById(`edit-latitude-input-${eid}`);
      const eLng = document.getElementById(`edit-longitude-input-${eid}`);
      const eRad = document.getElementById(`edit-radius-input-${eid}`);
      const eNum = document.getElementById(`edit-radius-number-${eid}`);
      const onEditChange = () => this.updateDraftCircle();

      if (eLat) {
        eLat.addEventListener("input", onEditChange);
        eLat.addEventListener("change", onEditChange);
      }
      if (eLng) {
        eLng.addEventListener("input", onEditChange);
        eLng.addEventListener("change", onEditChange);
      }
      if (eRad) {
        eRad.addEventListener("input", () => {
          if (eNum)
            eNum.value = String(Math.round(Number(eRad.value || 0) / 1000));
          this.updateDraftCircle();
        });
        eRad.addEventListener("change", () => {
          if (eNum)
            eNum.value = String(Math.round(Number(eRad.value || 0) / 1000));
          this.updateDraftCircle();
        });
      }
      if (eNum) {
        eNum.addEventListener("input", () => {
          if (eRad) eRad.value = String(Number(eNum.value || 0) * 1000);
          this.updateDraftCircle();
        });
        eNum.addEventListener("change", () => {
          if (eRad) eRad.value = String(Number(eNum.value || 0) * 1000);
          this.updateDraftCircle();
        });
      }
    };
    // Try initial attach (if edit mode already active)
    this.attachEditListeners();

    // Allow clicking on the map to populate the add-location form
    this.map.on("click", (e) => {
      const formLat = document.getElementById("latitude-input");
      const formLng = document.getElementById("longitude-input");
      // If editing, use the editing inputs instead
      const editingId = this.getEditingId();
      const editLat = editingId
        ? document.getElementById(`edit-latitude-input-${editingId}`)
        : null;
      const editLng = editingId
        ? document.getElementById(`edit-longitude-input-${editingId}`)
        : null;
      const latInput = editLat || formLat;
      const lngInput = editLng || formLng;
      if (!latInput || !lngInput) return;

      const { lat, lng } = e.latlng;
      latInput.value = Number(lat).toFixed(6);
      lngInput.value = Number(lng).toFixed(6);

      // Show a selection marker for visual feedback
      try {
        if (this.selectionMarker) {
          this.map.removeLayer(this.selectionMarker);
        }
        this.selectionMarker = L.marker([lat, lng], {
          icon: this.getEditingIcon(),
        }).addTo(this.map);
        this.updateDraftCircle();
      } catch (_err) {
        // no-op
      }
    });
  },
  updated() {
    // Invalidate map size when container changes
    setTimeout(() => {
      this.map.invalidateSize();
    }, 100);
    // Re-attach edit listeners if editing id changed
    this.attachEditListeners && this.attachEditListeners();
  },

  convertCompactFiresToObjects(compactData) {
    // Convert compact MessagePack format back to object format
    // Expected format: { format: "compact_v1", fields: ["lat", "lng", "timestamp", "confidence", "frp", "satellite"], data: [[...], [...]] }

    if (
      !compactData ||
      compactData.format !== "compact_v1" ||
      !compactData.data
    ) {
      console.warn("Invalid compact fire data format:", compactData);
      return [];
    }

    const fields = compactData.fields || [
      "lat",
      "lng",
      "timestamp",
      "confidence",
      "frp",
      "satellite",
    ];

    return compactData.data.map((fireArray) => {
      const fireObj = {};
      fields.forEach((field, index) => {
        if (field === "lat") fireObj.latitude = fireArray[index];
        else if (field === "lng") fireObj.longitude = fireArray[index];
        else if (field === "timestamp") {
          // Convert Unix timestamp back to ISO date string
          fireObj.detected_at = new Date(fireArray[index] * 1000).toISOString();
        } else {
          fireObj[field] = fireArray[index];
        }
      });
      return fireObj;
    });
  },

  updateMapData(locations, fires) {
    // Clear existing markers and circles
    this.markersLayer.clearLayers();
    this.fireCluster.clearLayers();

    // Add location markers (blue)
    locations.forEach((location) => {
      const latLng = [location.latitude, location.longitude];

      // Location marker (blue)
      const marker = L.marker(latLng).bindPopup(`
          <strong>📍 ${location.name}</strong><br>
          ${location.latitude.toFixed(4)}, ${location.longitude.toFixed(4)}<br>
          Monitoring radius: ${location.radius}m
        `);

      // Monitoring radius circle
      const circle = L.circle(latLng, {
        radius: location.radius,
        color: "#3b82f6",
        fillColor: "#3b82f6",
        fillOpacity: 0.1,
        weight: 2,
      });

      this.markersLayer.addLayer(marker);
      this.markersLayer.addLayer(circle);
    });

    // Add fire markers to cluster (red/orange)
    fires.forEach((fire) => {
      const lat = Number(fire.latitude);
      const lng = Number(fire.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;

      const latLng = [lat, lng];
      const frp = Number(fire.frp) || 0;
      const confidence = fire.confidence || "n";

      const detectedDate = fire.detected_at ? new Date(fire.detected_at) : null;
      const detectedText =
        detectedDate && !isNaN(detectedDate)
          ? detectedDate.toLocaleString()
          : "N/A";

      // Fire marker (red) - now added to cluster
      const fireMarker = L.circleMarker(latLng, {
        radius: Math.max(4, Math.min(frp / 5, 12)), // Size based on fire power
        color: "#dc2626",
        fillColor: this.getFireColor(confidence, frp),
        fillOpacity: 0.8,
        weight: 1,
      }).bindPopup(`
        <strong>🔥 Fire Detection</strong><br>
        <strong>Detected:</strong> ${detectedText}<br>
        <strong>Confidence:</strong> ${confidence}<br>
        <strong>Fire Power:</strong> ${frp} MW<br>
        <strong>Satellite:</strong> ${fire.satellite || "N/A"}<br>
        <strong>Coordinates:</strong> ${lat.toFixed(4)}, ${lng.toFixed(4)}
      `);

      // Store fire data on marker for cluster calculations
      fireMarker.fireData = {
        frp: frp,
        confidence: confidence,
        satellite: fire.satellite || "N/A",
      };

      this.fireCluster.addLayer(fireMarker);
    });

    // Set map view based on data
    if (locations.length === 0 && fires.length === 0) {
      // No data - world view
      this.map.setView([20, 0], 2);
    } else if (locations.length === 1 && fires.length === 0) {
      // Single location, no fires - zoom to location + radius
      const location = locations[0];
      const center = [location.latitude, location.longitude];
      const radiusMeters = location.radius + 3000;
      const zoom = this.getZoomForRadius(radiusMeters);
      this.map.setView(center, zoom);
    } else {
      // Multiple items - fit bounds to show all
      const bounds = L.latLngBounds();
      locations.forEach((location) =>
        bounds.extend([location.latitude, location.longitude])
      );
      fires.forEach((fire) => {
        const lat = Number(fire.latitude);
        const lng = Number(fire.longitude);
        if (Number.isFinite(lat) && Number.isFinite(lng)) {
          bounds.extend([lat, lng]);
        }
      });

      if (bounds.isValid()) {
        this.map.fitBounds(bounds, { padding: [50, 50], maxZoom: 14 });
      }
    }

    // Invalidate size after bounds change
    setTimeout(() => {
      this.map.invalidateSize();
    }, 100);
  },

  getEditingIcon() {
    // Simple colored marker using a div icon for draft/edited state
    return L.divIcon({
      className: "draft-marker",
      html: '<div style="width:12px;height:12px;border-radius:9999px;background:#2563eb;box-shadow:0 0 0 3px rgba(37,99,235,0.3)"></div>',
      iconSize: [12, 12],
      iconAnchor: [6, 6],
    });
  },

  updateDraftCircle() {
    const eid = this.getEditingId();
    const latInput = eid
      ? document.getElementById(`edit-latitude-input-${eid}`)
      : document.getElementById("latitude-input");
    const lngInput = eid
      ? document.getElementById(`edit-longitude-input-${eid}`)
      : document.getElementById("longitude-input");
    const radiusInput = eid
      ? document.getElementById(`edit-radius-input-${eid}`)
      : document.getElementById("radius-input");
    const radiusNumberEl = eid
      ? document.getElementById(`edit-radius-number-${eid}`)
      : document.getElementById("radius-number");
    const radiusValueEl = eid
      ? document.getElementById(`edit-radius-value-${eid}`)
      : document.getElementById("radius-value");
    if (!latInput || !lngInput || !radiusInput) return;

    const lat = Number(latInput.value);
    const lng = Number(lngInput.value);
    const radius = Number(
      radiusInput.value || radiusInput.getAttribute("value") || 0
    );
    if (
      radiusNumberEl &&
      radiusNumberEl.value !== String(Math.round(radius / 1000))
    ) {
      radiusNumberEl.value = String(Math.round(radius / 1000));
    }
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || radius <= 0) return;

    if (radiusValueEl)
      radiusValueEl.textContent = String(Math.round(radius / 1000));

    // Place or update selection marker
    try {
      if (!this.selectionMarker) {
        this.selectionMarker = L.marker([lat, lng], {
          icon: this.getEditingIcon(),
        }).addTo(this.map);
      } else {
        this.selectionMarker.setLatLng([lat, lng]);
      }
    } catch (_err) {}

    // Update draft circle
    try {
      if (this.draftCircle) {
        this.map.removeLayer(this.draftCircle);
      }
      this.draftCircle = L.circle([lat, lng], {
        radius,
        color: "#2563eb",
        fillColor: "#2563eb",
        fillOpacity: 0.08,
        weight: 2,
        dashArray: "4 4",
      }).addTo(this.map);
    } catch (_err) {}
  },

  getEditingId() {
    const attr = this.el.dataset.editingId;
    if (attr && attr !== "" && attr !== "nil") return attr;
    const form = document.querySelector("form[id^='edit-location-form-']");
    if (form) {
      const m = form.id.match(/edit-location-form-(.+)$/);
      if (m) return m[1];
    }
    return null;
  },

  getFireColor(confidence, frp) {
    // Color based on confidence and fire power
    if (confidence === "h" && frp > 20) return "#dc2626"; // High confidence, high power - bright red
    if (confidence === "h") return "#f97316"; // High confidence - orange
    if (frp > 20) return "#ea580c"; // High power - dark orange
    return "#fb923c"; // Normal - light orange
  },

  getClusterColor(count, avgIntensity) {
    // Calculate cluster color based on fire count and average intensity
    // avgIntensity is a score from 0-100 based on FRP and confidence

    // Base red intensity on fire count
    let baseIntensity;
    if (count >= 50) baseIntensity = 1.0;
    else if (count >= 20) baseIntensity = 0.9;
    else if (count >= 10) baseIntensity = 0.8;
    else if (count >= 5) baseIntensity = 0.7;
    else baseIntensity = 0.6;

    // Adjust for average fire intensity (0-100 scale)
    const intensityMultiplier = 0.5 + avgIntensity / 200; // 0.5 to 1.0
    const finalIntensity = Math.min(1.0, baseIntensity * intensityMultiplier);

    // Generate red shades - darker red for higher intensity
    const red = Math.round(139 + 116 * finalIntensity); // 139 to 255
    const green = Math.round(26 * (1 - finalIntensity * 0.8)); // 26 to ~5
    const blue = Math.round(26 * (1 - finalIntensity * 0.8)); // 26 to ~5

    return `rgb(${red}, ${green}, ${blue})`;
  },

  calculateFireIntensity(fireData) {
    // Calculate intensity score (0-100) based on FRP and confidence
    let score = 0;

    // FRP contribution (0-70 points)
    const frp = fireData.frp || 0;
    if (frp > 50) score += 70;
    else if (frp > 20) score += 50 + ((frp - 20) / 30) * 20;
    else if (frp > 5) score += 30 + ((frp - 5) / 15) * 20;
    else score += (frp / 5) * 30;

    // Confidence contribution (0-30 points)
    const confidence = fireData.confidence || "n";
    if (confidence === "h") score += 30;
    else if (confidence === "n") score += 15;
    else score += 5; // low confidence

    return Math.min(100, score);
  },

  createFireClusterIcon(cluster) {
    const markers = cluster.getAllChildMarkers();
    const count = markers.length;

    // Calculate average intensity from fire data
    let totalIntensity = 0;
    let validMarkers = 0;

    markers.forEach((marker) => {
      if (marker.fireData) {
        totalIntensity += this.calculateFireIntensity(marker.fireData);
        validMarkers++;
      }
    });

    const avgIntensity = validMarkers > 0 ? totalIntensity / validMarkers : 50;
    const color = this.getClusterColor(count, avgIntensity);

    // Size based on count
    let size;
    if (count >= 100) size = 50;
    else if (count >= 50) size = 45;
    else if (count >= 20) size = 40;
    else if (count >= 10) size = 35;
    else size = 30;

    return L.divIcon({
      html: `<div style="
        width: ${size}px;
        height: ${size}px;
        background-color: ${color};
        border: 2px solid #7f1d1d;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        color: white;
        font-weight: bold;
        font-size: ${Math.max(12, size * 0.4)}px;
        text-shadow: 1px 1px 1px rgba(0,0,0,0.7);
        box-shadow: 0 2px 8px rgba(0,0,0,0.3);
      ">🔥</div>`,
      className: "fire-cluster-icon",
      iconSize: [size, size],
      iconAnchor: [size / 2, size / 2],
    });
  },

  getZoomForRadius(radiusMeters) {
    // Approximate zoom levels for different radius sizes
    if (radiusMeters > 50000) return 8; // > 50km
    if (radiusMeters > 20000) return 10; // > 20km
    if (radiusMeters > 10000) return 11; // > 10km
    if (radiusMeters > 5000) return 12; // > 5km
    if (radiusMeters > 2000) return 13; // > 2km
    return 14; // < 2km
  },
};

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
